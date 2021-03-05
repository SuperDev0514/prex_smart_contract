
pragma solidity 0.5.7;

import "./external/uniswap/solidity-interface.sol";
import "./external/uniswap/FixedPoint.sol";
import "./external/uniswap/oracleLibrary.sol";
import "./external/openzeppelin-solidity/math/SafeMath.sol";
import "./external/proxy/OwnedUpgradeabilityProxy.sol";
import "./interfaces/ITokenController.sol";
import "./interfaces/IMarketRegistry.sol";
import "./interfaces/IChainLinkOracle.sol";
import "./interfaces/IToken.sol";

contract MarketUtility {
  using SafeMath for uint256;
  using FixedPoint for *;
  
  address constant ETH_ADDRESS = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
  uint256 constant updatePeriod = 1 hours;

  uint256 internal STAKE_WEIGHTAGE;
  uint256 internal STAKE_WEIGHTAGE_MIN_AMOUNT;
  uint256 internal minTimeElapsedDivisor;
  uint256 internal minPredictionAmount;
  uint256 internal maxPredictionAmount;
  uint256 internal positionDecimals;
  uint256 internal minStakeForMultiplier;
  uint256 internal riskPercentage;
  uint256 internal tokenStakeForDispute;
  address internal plotToken;
  address internal plotETHpair;
  address internal weth;
  address internal initiater;
  address public authorizedAddress;
  bool public initialized;


  struct UniswapPriceData {
    FixedPoint.uq112x112 price0Average;
    uint256 price0CumulativeLast;
    FixedPoint.uq112x112 price1Average;
    uint256 price1CumulativeLast;
    uint32 blockTimestampLast;
    bool initialized;
  }

  mapping(address => UniswapPriceData) internal uniswapPairData;
  IUniswapV2Factory uniswapFactory;

  ITokenController internal tokenController;
  modifier onlyAuthorized() {
    require(msg.sender == authorizedAddress, "Not authorized");
    _;
  }
  
  /**
    * @dev Initiates the config contact with initial values
    **/
  function initialize(address payable[] memory _addressParams, address _initiater) public {
    OwnedUpgradeabilityProxy proxy = OwnedUpgradeabilityProxy(
        address(uint160(address(this)))
    );
    require(msg.sender == proxy.proxyOwner(), "Sender is not proxy owner.");
    require(!initialized, "Already initialized");
    initialized = true;
    _setInitialParameters();
    authorizedAddress = msg.sender;
    tokenController = ITokenController(IMarketRegistry(msg.sender).tokenController());
    plotToken = _addressParams[1];
    initiater = _initiater;
    weth = IUniswapV2Router02(_addressParams[0]).WETH();
    uniswapFactory = IUniswapV2Factory(_addressParams[2]);
  }
  
  /**
    * @dev Internal function to set initial value
    **/
  function _setInitialParameters() internal {
    STAKE_WEIGHTAGE = 40; //
    STAKE_WEIGHTAGE_MIN_AMOUNT = 20 ether;
    minTimeElapsedDivisor = 6;
    minPredictionAmount = 1e15;
    maxPredictionAmount = 28 ether;
    positionDecimals = 1e2;
    minStakeForMultiplier = 5e17;
    riskPercentage = 20;
    tokenStakeForDispute = 500 ether;
  }

  /**
  * @dev Calculate the prediction value, passing all the required params
  * params index
  * 0 _prediction
  * 1 neutralMinValue
  * 2 neutralMaxValue
  * 3 startTime
  * 4 expireTime
  * 5 totalStakedETH
  * 6 totalStakedToken
  * 7 ethStakedOnOption
  * 8 plotStakedOnOption
  * 9 _stake
  * 10 _leverage
  */
  function calculatePredictionValue(uint[] memory params, address asset, address user, address marketFeedAddress, bool _checkMultiplier) public view returns(uint _predictionValue, bool _multiplierApplied) {
    uint _stakeValue = getAssetValueETH(asset, params[9]);
    if(_stakeValue < minPredictionAmount || _stakeValue > maxPredictionAmount) {
      return (_predictionValue, _multiplierApplied);
    }
    uint optionPrice;
    
    optionPrice = calculateOptionPrice(params, marketFeedAddress);
    _predictionValue = _calculatePredictionPoints(_stakeValue.mul(positionDecimals), optionPrice, params[10]);
    if(_checkMultiplier) {
      return checkMultiplier(asset, user, params[9],  _predictionValue, _stakeValue);
    }
    return (_predictionValue, _multiplierApplied);
  }

  function _calculatePredictionPoints(uint value, uint optionPrice, uint _leverage) internal pure returns(uint) {
    //leverageMultiplier = levergage + (leverage -1)*0.05; Raised by 3 decimals i.e 1000
    uint leverageMultiplier = 1000 + (_leverage-1)*50;
    value = value.mul(2500).div(1e18);
    // (amount*sqrt(amount*100)*leverage*100/(price*10*125000/1000));
    return value.mul(sqrt(value.mul(10000))).mul(_leverage*100*leverageMultiplier).div(optionPrice.mul(1250000000));
  }

}