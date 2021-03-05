
pragma solidity 0.5.7;

import "./external/openzeppelin-solidity/math/SafeMath.sol";
import "./external/proxy/OwnedUpgradeabilityProxy.sol";
import "./interfaces/IToken.sol";
import "./interfaces/ITokenController.sol";
import "./interfaces/IMarketRegistry.sol";

contract Market {
  using SafeMath for *;

  enum PredictionStatus {
    Live,
    InSettlement,
    Cooling,
    InDispute,
    Settled
  }
  
  struct option
  {
    uint predictionPoints;
    mapping(address => uint256) assetStaked;
    mapping(address => uint256) assetLeveraged;
  }

  struct MarketSettleData {
    uint64 WinningOption;
    uint64 settleTime;
  }

  struct MarketData {
    uint64 startTime;
    uint64 predictionTime;
    uint64 neutralMinValue;
    uint64 neutralMaxValue;
  }

  uint constant totalOptions = 3;
  uint constant MAX_LEVERAGE = 5;
  uint constant ethCommissionPerc = 10; //with 2 decimals
  uint constant busdCommissionPerc = 5; //with 2 decimals
  bytes32 public constant marketCurrency = "ETH/USDT";
  
  address constant ETH_ADDRESS = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
  address constant marketFeedAddress = 0x5e2aa6b66531142bEAB830c385646F97fa03D80a;
  address constant BUSD_ADDRESS = 0x4Fabb145d64652a948d72533023f6E7A623C7C53;

  address internal incentiveToken;
  uint internal ethAmountToPool;
  uint internal ethCommissionAmount;
  uint internal busdCommissionAmount;
  uint internal tokenAmountToPool;
  
  PredictionStatus internal predictionStatus;
  MarketData public marketData;
  MarketSettleData public marketSettleData;

  mapping(address => UserData) internal userData;
  mapping(uint=>option) public optionsAvailable;

  /**
    * @dev Initialize the market.
    * @param _startTime The time at which market will create.
    * @param _predictionTime The time duration of market.
    * @param _minValue The minimum value of neutral option range.
    * @param _maxValue The maximum value of neutral option range.
    */
  function initiate(uint64 _startTime, uint64 _predictionTime, uint64 _minValue, uint64 _maxValue) public payable {
    OwnedUpgradeabilityProxy proxy = OwnedUpgradeabilityProxy(address(uint160(address(this))));
    require(msg.sender == proxy.proxyOwner(),"Sender is not proxy owner.");
    require(marketData.startTime == 0, "Already initialized");
    require(_startTime.add(_predictionTime) > now);
    marketData.startTime = _startTime;
    marketData.predictionTime = _predictionTime;
    
    marketData.neutralMinValue = _minValue;
    marketData.neutralMaxValue = _maxValue;
  }

  /**
    * @dev Place prediction on the available options of the market.
    * @param _asset The asset used by user during prediction whether it is plotToken address or in ether.
    * @param _predictionStake The amount staked by user at the time of prediction.
    * @param _prediction The option on which user placed prediction.
    * @param _leverage The leverage opted by user at the time of prediction.
    */
  function placePrediction(address _asset, uint256 _predictionStake, uint256 _prediction, uint256 _leverage) public payable {
    require(!marketRegistry.marketCreationPaused() && _prediction <= totalOptions && _leverage <= MAX_LEVERAGE);
    require(now >= marketData.startTime && now <= marketExpireTime());

    uint256 _commissionStake;
    if(_asset == ETH_ADDRESS) {
      require(_predictionStake == msg.value);
      _commissionStake = _calculatePercentage(ethCommissionPerc, _predictionStake, 10000);
      ethCommissionAmount = ethCommissionAmount.add(_commissionStake);
    } else {
      require(msg.value == 0);
      require(_asset == BUSD_ADDRESS);
      _commissionStake = _calculatePercentage(busdCommissionPerc, _predictionStake, 10000);
      busdCommissionAmount = busdCommissionAmount.add(_commissionStake);
    }
    _commissionStake = _predictionStake.sub(_commissionStake);

    (uint predictionPoints, bool isMultiplierApplied) = calculatePredictionValue(_prediction, _commissionStake, _leverage, _asset);
    if(isMultiplierApplied) {
      userData[msg.sender].multiplierApplied = true; 
    }
    require(predictionPoints > 0);

    _storePredictionData(_prediction, _commissionStake, _asset, _leverage, predictionPoints);
    marketRegistry.setUserGlobalPredictionData(msg.sender,_predictionStake, predictionPoints, _asset, _prediction, _leverage);
  }

  function _calculatePercentage(uint256 _percent, uint256 _value, uint256 _divisor) internal pure returns(uint256) {
    return _percent.mul(_value).div(_divisor);
  }

  function calculatePredictionValue(uint _prediction, uint _predictionStake, uint _leverage, address _asset) internal view returns(uint predictionPoints, bool isMultiplierApplied) {
      uint[] memory params = new uint[](11);
      params[0] = _prediction;
      params[1] = marketData.neutralMinValue;
      params[2] = marketData.neutralMaxValue;
      params[3] = marketData.startTime;
      params[4] = marketExpireTime();
      (params[5], params[6]) = getTotalAssetsStaked();
      params[7] = optionsAvailable[_prediction].assetStaked[ETH_ADDRESS];
      params[8] = optionsAvailable[_prediction].assetStaked[plotToken];
      params[9] = _predictionStake;
      params[10] = _leverage;
      bool checkMultiplier;
      if(!userData[msg.sender].multiplierApplied) {
        checkMultiplier = true;
      }
      (predictionPoints, isMultiplierApplied) = marketUtility.calculatePredictionValue(params, _asset, msg.sender, marketFeedAddress, checkMultiplier);
      
    }
}