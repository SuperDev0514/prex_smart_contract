
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
    //mapping(address => uint256) assetLeveraged;
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
  uint constant plexCommissionPerc = 5; //with 2 decimals
  bytes32 public constant marketCurrency = "ETH/USDT";
  
  address constant ETH_ADDRESS = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
  address constant marketFeedAddress = 0x5e2aa6b66531142bEAB830c385646F97fa03D80a;
  address constant PLEX_ADDRESS = 0x4Fabb145d64652a948d72533023f6E7A623C7C53;

  IMarketRegistry constant marketRegistry = IMarketRegistry(0x65Add15C5Ff3Abc069358AAe842dE13Ce92f3447);
  //ITokenController constant tokenController = ITokenController(0x3A3d9ca9d9b25AF1fF7eB9d8a1ea9f61B5892Ee9);
  IERC20 plexToken = IERC20(PLEX_ADDRESS);
  IMarketUtility constant marketUtility = IMarketUtility(0xCBc7df3b8C870C5CDE675AaF5Fd823E4209546D2);

  address internal incentiveToken;
  uint internal ethAmountToPool;
  uint internal ethCommissionAmount;
  uint internal plexCommissionAmount;
  uint internal tokenAmountToPool;
  uint[] internal rewardToDistribute;
  
  PredictionStatus internal predictionStatus;
  MarketData public marketData;
  MarketSettleData public marketSettleData;

  mapping(address => UserData) internal userData;
  mapping(uint => option) public optionsAvailable;

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
    * @param _asset The asset used by user during prediction whether it is PLEX_ADDRESS address or in ether.
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
      require(_asset == PLEX_ADDRESS);
      plexToken.transferFrom(msg.sender, address(this), _predictionStake);
      _commissionStake = _calculatePercentage(plexCommissionPerc, _predictionStake, 10000);
      plexCommissionAmount = plexCommissionAmount.add(_commissionStake);
    }
    _commissionStake = _predictionStake.sub(_commissionStake);

    uint256 predictionPoints = marketUtility.getAssetValueETH(_asset, _commissionStake);
    require(predictionPoints > 0);

    _storePredictionData(_prediction, _commissionStake, _asset, _leverage, predictionPoints);
  }

  
  /**
    * @dev Calculate the result of market.
    * @param _value The current price of market currency.
    */
  function _postResult(uint256 _value, uint256 _roundId) internal {
    require(now >= marketSettleTime(),"Time not reached");
    require(_value > 0,"value should be greater than 0");
    
    marketSettleData.settleTime = uint64(now);
    predictionStatus = PredictionStatus.Settled;
    if(_value < marketData.neutralMinValue) {
      marketSettleData.WinningOption = 1;
    } else if(_value > marketData.neutralMaxValue) {
      marketSettleData.WinningOption = 3;
    } else {
      marketSettleData.WinningOption = 2;
    }
    uint[] memory totalReward = new uint256[](2);
    if(optionsAvailable[marketSettleData.WinningOption].assetStaked[ETH_ADDRESS] > 0 ||
      optionsAvailable[marketSettleData.WinningOption].assetStaked[PLEX_ADDRESS] > 0
    ){
      for(uint i = 1; i <= totalOptions; i++){
        if(i != marketSettleData.WinningOption) {
          totalReward[0] = totalReward[0].add(optionsAvailable[i].assetStaked[PLEX_ADDRESS]);
          totalReward[1] = totalReward[1].add(optionsAvailable[i].assetStaked[ETH_ADDRESS]);
        }
      }
      rewardToDistribute = totalReward;
    }
    _transferAsset(ETH_ADDRESS, address(marketRegistry), ethAmountToPool.add(ethCommissionAmount));
    _transferAsset(PLEX_ADDRESS, address(marketRegistry), tokenAmountToPool.add(plexCommissionAmount));
    delete ethCommissionAmount;
    delete plexCommissionAmount;
    marketRegistry.callMarketResultEvent(rewardToDistribute, marketSettleData.WinningOption, _value, _roundId);
  }

  function _calculatePercentage(uint256 _percent, uint256 _value, uint256 _divisor) internal pure returns(uint256) {
    return _percent.mul(_value).div(_divisor);
  }

  /**
    * @dev Stores the prediction data.
    * @param _prediction The option on which user place prediction.
    * @param _predictionStake The amount staked by user at the time of prediction.
    * @param _asset The asset used by user during prediction.
    * @param _leverage The leverage opted by user during prediction.
    * @param predictionPoints The positions user got during prediction.
    */
  function _storePredictionData(uint _prediction, uint _predictionStake, address _asset, uint _leverage, uint predictionPoints) internal {
    userData[msg.sender].predictionPoints[_prediction] = userData[msg.sender].predictionPoints[_prediction].add(predictionPoints);
    userData[msg.sender].assetStaked[_asset][_prediction] = userData[msg.sender].assetStaked[_asset][_prediction].add(_predictionStake);
    //userData[msg.sender].LeverageAsset[_asset][_prediction] = userData[msg.sender].LeverageAsset[_asset][_prediction].add(_predictionStake.mul(_leverage));
    optionsAvailable[_prediction].predictionPoints = optionsAvailable[_prediction].predictionPoints.add(predictionPoints);
    optionsAvailable[_prediction].assetStaked[_asset] = optionsAvailable[_prediction].assetStaked[_asset].add(_predictionStake);
    //optionsAvailable[_prediction].assetLeveraged[_asset] = optionsAvailable[_prediction].assetLeveraged[_asset].add(_predictionStake.mul(_leverage));
  }
  
  /**
    * @dev Settle the market, setting the winning option
    */
  function settleMarket() external {
    (uint256 _value, uint256 _roundId) = marketUtility.getSettlementPrice(marketFeedAddress, uint256(marketSettleTime()));
    if(marketStatus() == PredictionStatus.InSettlement) {
      _postResult(_value, _roundId);
    }
  }

  /**
    * @dev Claim the return amount of the specified address.
    * @param _user The address to query the claim return amount of.
    * @return Flag, if 0:cannot claim, 1: Already Claimed, 2: Claimed
    */
  function claimReturn(address payable _user) public returns(uint256) {

    if(marketStatus() != PredictionStatus.Settled || marketRegistry.marketCreationPaused()) {
      return 0;
    }
    if(userData[_user].claimedReward) {
      return 1;
    }
    userData[_user].claimedReward = true;
    (uint[] memory _returnAmount, address[] memory _predictionAssets, uint _incentive, ) = getReturn(_user);
    _transferAsset(PLEX_ADDRESS, _user, _returnAmount[0]);
    _transferAsset(ETH_ADDRESS, _user, _returnAmount[1]);
    marketRegistry.callClaimedEvent(_user, _returnAmount, _predictionAssets, _incentive, incentiveToken);
    return 2;
  }

  /**
    * @dev Transfer the assets to specified address.
    * @param _asset The asset transfer to the specific address.
    * @param _recipient The address to transfer the asset of
    * @param _amount The amount which is transfer.
    */
  function _transferAsset(address _asset, address payable _recipient, uint256 _amount) internal {
    if(_amount > 0) { 
      if(_asset == ETH_ADDRESS) {
        _recipient.transfer(_amount);
      } else {
        require(IToken(_asset).transfer(_recipient, _amount));
      }
    }
  }

  /**
  * @dev Gets the result of the market.
  * @return uint256 representing the winning option of the market.
  * @return uint256 Value of market currently at the time closing market.
  * @return uint256 representing the positions of the winning option.
  * @return uint[] memory representing the reward to be distributed.
  * @return uint256 representing the Eth staked on winning option.
  * @return uint256 representing the PLOT staked on winning option.
  */
  function getMarketResults() public view returns(uint256, uint256, uint256[] memory, uint256, uint256) {
    return (marketSettleData.WinningOption, optionsAvailable[marketSettleData.WinningOption].predictionPoints, rewardToDistribute, optionsAvailable[marketSettleData.WinningOption].assetStaked[ETH_ADDRESS], optionsAvailable[marketSettleData.WinningOption].assetStaked[plotToken]);
  }

  /**
  * @dev Gets the return amount of the specified address.
  * @param _user The address to specify the return of
  * @return returnAmount uint[] memory representing the return amount.
  * @return incentive uint[] memory representing the amount incentive.
  * @return _incentiveTokens address[] memory representing the incentive tokens.
  */
  function getReturn(address _user)public view returns (uint[] memory returnAmount, address[] memory _predictionAssets, uint incentive, address _incentiveToken){
    (uint256 ethStaked, uint256 plotStaked) = getTotalAssetsStaked();
    if(marketStatus() != PredictionStatus.Settled || ethStaked.add(plotStaked) == 0) {
      return (returnAmount, _predictionAssets, incentive, incentiveToken);
    }
    _predictionAssets = new address[](2);
    _predictionAssets[0] = PLEX_ADDRESS;
    _predictionAssets[1] = ETH_ADDRESS;

    uint256 _totalUserPredictionPoints = 0;
    uint256 _totalPredictionPoints = 0;
    (returnAmount, _totalUserPredictionPoints, _totalPredictionPoints) = _calculateUserReturn(_user);
    incentive = _calculateIncentives(_totalUserPredictionPoints, _totalPredictionPoints);
    if(userData[_user].predictionPoints[marketSettleData.WinningOption] > 0) {
      returnAmount = _addUserReward(_user, returnAmount);
    }
    return (returnAmount, _predictionAssets, incentive, incentiveToken);
  }

  function getTotalAssetsStaked() public view returns(uint256 ethStaked, uint256 plotStaked) {
    for(uint256 i = 1; i<= totalOptions;i++) {
      ethStaked = ethStaked.add(optionsAvailable[i].assetStaked[ETH_ADDRESS]);
      plotStaked = plotStaked.add(optionsAvailable[i].assetStaked[PLEX_ADDRESS]);
    }
  }

  function getTotalStakedValueInPLOT() public view returns(uint256) {
    (uint256 ethStaked, uint256 plotStaked) = getTotalAssetsStaked();
    (, ethStaked) = marketUtility.getValueAndMultiplierParameters(ETH_ADDRESS, ethStaked);
    return plotStaked.add(ethStaked);
  }

  /**
  * @dev Get flags set for user
  * @param _user User address
  * @return Flag defining if user had availed multiplier
  * @return Flag defining if user had predicted with bPLOT
  */
  function getUserFlags(address _user) external view returns(bool, bool) {
    return (userData[_user].multiplierApplied, userData[_user].predictedWithBlot);
  }

  /**
  * @dev Adds the reward in the total return of the specified address.
  * @param _user The address to specify the return of.
  * @param returnAmount The return amount.
  * @return uint[] memory representing the return amount after adding reward.
  */
  function _addUserReward(address _user, uint[] memory returnAmount) internal view returns(uint[] memory){
    uint reward;
    for(uint j = 0; j< returnAmount.length; j++) {
      reward = userData[_user].predictionPoints[marketSettleData.WinningOption].mul(rewardToDistribute[j]).div(optionsAvailable[marketSettleData.WinningOption].predictionPoints);
      returnAmount[j] = returnAmount[j].add(reward);
    }
    return returnAmount;
  }
  
  /**
  * @dev Calculate the return of the specified address.
  * @param _user The address to query the return of.
  * @return _return uint[] memory representing the return amount owned by the passed address.
  * @return _totalUserPredictionPoints uint representing the positions owned by the passed address.
  * @return _totalPredictionPoints uint representing the total positions of winners.
  */
  function _calculateUserReturn(address _user) internal view returns(uint[] memory _return, uint _totalUserPredictionPoints, uint _totalPredictionPoints){
    _return = new uint256[](2);
    for(uint i = 1; i <= totalOptions; i++){
      _totalUserPredictionPoints = _totalUserPredictionPoints.add(userData[_user].predictionPoints[i]);
      _totalPredictionPoints = _totalPredictionPoints.add(optionsAvailable[i].predictionPoints);
      
      if (i == marketSettleData.WinningOption) {
        _return[0].add(userData[_user].assetStaked[PLEX_ADDRESS][i]);
        _return[1].add(userData[_user].assetStaked[ETH_ADDRESS][i]);
      }
    }
  }

  /**
  * @dev Calculates the incentives.
  * @param _totalUserPredictionPoints The positions of user.
  * @param _totalPredictionPoints The total positions of winners.
  * @return incentive the calculated incentive.
  */
  function _calculateIncentives(uint256 _totalUserPredictionPoints, uint256 _totalPredictionPoints) internal view returns(uint256 incentive){
    incentive = _totalUserPredictionPoints.mul(incentiveToDistribute.div(_totalPredictionPoints));
  }

  /**
    * @dev Get market settle time
    * @return the time at which the market result will be declared
    */
  function marketSettleTime() public view returns(uint64) {
    if(marketSettleData.settleTime > 0) {
      return marketSettleData.settleTime;
    }
    return uint64(marketData.startTime.add(marketData.predictionTime.mul(2)));
  }

  /**
    * @dev Get market expire time
    * @return the time upto which user can place predictions in market
    */
  function marketExpireTime() internal view returns(uint256) {
    return marketData.startTime.add(marketData.predictionTime);
  }

  /**
    * @dev Get market cooldown time
    * @return the time upto which user can raise the dispute after the market is settled
    */
  function marketCoolDownTime() public view returns(uint256) {
    return marketSettleData.settleTime.add(marketData.predictionTime.div(4));
  }
  
  /**
  * @dev Gets the status of market.
  * @return PredictionStatus representing the status of market.
  */
  function marketStatus() internal view returns(PredictionStatus){
    if(predictionStatus == PredictionStatus.Live && now >= marketExpireTime()) {
      return PredictionStatus.InSettlement;
    } else if(predictionStatus == PredictionStatus.Settled && now <= marketCoolDownTime()) {
      return PredictionStatus.Cooling;
    }
    return predictionStatus;
  }
}