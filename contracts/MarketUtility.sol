
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
  address internal plexToken;
  address internal plexETHpair;
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
    plexToken = _addressParams[1];
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
    * @dev Get price of provided feed address
    * @param _currencyFeedAddress  Feed Address of currency on which market options are based on
    * @return Current price of the market currency
    **/
  function getSettlemetPrice(
    address _currencyFeedAddress,
    uint256 _settleTime
  ) public view returns (uint256 latestAnswer, uint256 roundId) {
    uint80 currentRoundId;
    uint256 currentRoundTime;
    int256 currentRoundAnswer;
    (currentRoundId, currentRoundAnswer, , currentRoundTime, )= IChainLinkOracle(_currencyFeedAddress).latestRoundData();
    while(currentRoundTime > _settleTime) {
      currentRoundId--;
      (currentRoundId, currentRoundAnswer, , currentRoundTime, )= IChainLinkOracle(_currencyFeedAddress).getRoundData(currentRoundId);
      if(currentRoundTime <= _settleTime) {
        break;
      }
    }
    return
      (uint256(currentRoundAnswer), currentRoundId);
  }

  /**
    * @dev Get value of provided currency address in ETH
    * @param _currencyAddress Address of currency
    * @param _amount Amount of provided currency
    * @return Value of provided amount in ETH
    **/
  function getAssetValueETH(address _currencyAddress, uint256 _amount)
    public
    view
    returns (uint256 tokenEthValue)
  {
    tokenEthValue = _amount;
    if (_currencyAddress != ETH_ADDRESS) {
        tokenEthValue = getPrice(plexETHpair, _amount);
    }
  }
  
  /**
    * @dev Get price of provided currency address in ETH
    * @param _currencyAddress Address of currency
    * @return Price of provided currency in ETH
    * @return Decimals of the currency
    **/
  function getAssetPriceInETH(address _currencyAddress)
    public
    view
    returns (uint256 tokenEthValue, uint256 decimals)
  {
    tokenEthValue = 1;
    if (_currencyAddress != ETH_ADDRESS) {
      decimals = IToken(_currencyAddress).decimals();
      tokenEthValue = getPrice(plexETHpair, 10**decimals);
    }
  }
  
  /**
    * @dev Get price of provided feed address
    * @param _currencyFeedAddress  Feed Address of currency on which market options are based on
    * @return Current price of the market currency
    **/
  function getAssetPriceUSD(
    address _currencyFeedAddress
  ) public view returns (uint256 latestAnswer) {
    return uint256(IChainLinkOracle(_currencyFeedAddress).latestAnswer());
  }


  /**
    * @dev Get value of token in pair
    **/
  function getPrice(address pair, uint256 amountIn)
    public
    view
    returns (uint256 amountOut)
  {
    amountOut = (uniswapPairData[pair].price0Average)
      .mul(amountIn)
      .decode144();
  }

}