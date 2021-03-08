
pragma solidity 0.5.7;

import "./external/openzeppelin-solidity/math/SafeMath.sol";
import "./external/govblocks-protocol/interfaces/IGovernance.sol";
import "./external/govblocks-protocol/Governed.sol";
import "./external/proxy/OwnedUpgradeabilityProxy.sol";
import "./interfaces/IToken.sol";
import "./interfaces/IMarket.sol";
import "./interfaces/Iupgradable.sol";

contract MarketRegistry is Governed, Iupgradable {

    using SafeMath for *; 

    enum MarketType {
      HourlyMarket,
      DailyMarket,
      WeeklyMarket
    }

    struct MarketTypeData {
      uint64 predictionTime;
      uint64 optionRangePerc;
    }

    struct MarketCreationData {
      uint64 initialStartTime;
      address marketAddress;
      address penultimateMarket;
    }

    struct MarketData {
      bool isMarket;
    }

    struct UserData {
      uint256 lastClaimedIndex;
      uint256 marketsCreated;
      uint256 totalEthStaked;
      uint256 totalPlotStaked;
      address[] marketsParticipated;
      mapping(address => bool) marketsParticipatedFlag;
    }

    uint internal marketCreationIncentive;
    
    mapping(address => MarketData) marketData;
    mapping(address => UserData) userData;
    mapping(uint256 => mapping(uint256 => MarketCreationData)) public marketCreationData;

    address constant ETH_ADDRESS = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    address internal marketInitiater;
    address public tokenController;

    MarketCurrency[] marketCurrencies;
    MarketTypeData[] marketTypes;

    bool public marketCreationPaused;

    IToken public plotToken;
    IGovernance internal governance;
    IMaster ms;

    /**
    * @dev Checks if given addres is valid market address.
    */
    function isMarket(address _address) public view returns(bool) {
      return marketData[_address].isMarket;
    }
    
    /**
    * @dev Initialize the PlotX MarketRegistry.
    * @param _defaultAddress Address authorized to start initial markets
    * @param _marketUtility The address of market config.
    * @param _plotToken The instance of PlotX token.
    */
    function initiate(address _defaultAddress, address _marketUtility, address _plotToken, address payable[] memory _configParams) public {
      require(address(ms) == msg.sender);
      marketCreationIncentive = 50 ether;
      plotToken = IToken(_plotToken);
      address tcAddress = ms.getLatestAddress("TC");
      tokenController = tcAddress;
      marketUtility = IMarketUtility(_generateProxy(_marketUtility));
      marketUtility.initialize(_configParams, _defaultAddress);
      marketInitiater = _defaultAddress;
    }
    
    /**
    * @dev Creates the new market
    * @param _marketType The type of the market.
    * @param _marketCurrencyIndex the index of market currency.
    */
    function createMarket(uint256 _marketType) public payable{
      address penultimateMarket = marketCreationData[_marketType][_marketCurrencyIndex].penultimateMarket;
      if(penultimateMarket != address(0)) {
        IMarket(penultimateMarket).settleMarket();
      }
      if(marketCreationData[_marketType][_marketCurrencyIndex].marketAddress != address(0)) {
        (,,,,,,,, uint _status) = getMarketDetails(marketCreationData[_marketType][_marketCurrencyIndex].marketAddress);
        require(_status >= uint(IMarket.PredictionStatus.InSettlement));
      }
      (uint8 _roundOfToNearest, bytes32 _currencyName, address _priceFeed) = IMarket(marketCurrencies[_marketCurrencyIndex].marketImplementation).getMarketFeedData();
      marketUtility.update();
      uint64 _marketStartTime = calculateStartTimeForMarket(_marketType, _marketCurrencyIndex);
      uint64 _optionRangePerc = marketTypes[_marketType].optionRangePerc;
      uint currentPrice = marketUtility.getAssetPriceUSD(_priceFeed);
      _optionRangePerc = uint64(currentPrice.mul(_optionRangePerc.div(2)).div(10000));
      uint64 _decimals = marketCurrencies[_marketCurrencyIndex].decimals;
      uint64 _minValue = uint64((ceil(currentPrice.sub(_optionRangePerc).div(_roundOfToNearest), 10**_decimals)).mul(_roundOfToNearest));
      uint64 _maxValue = uint64((ceil(currentPrice.add(_optionRangePerc).div(_roundOfToNearest), 10**_decimals)).mul(_roundOfToNearest));
      _createMarket(_marketType, _marketCurrencyIndex, _minValue, _maxValue, _marketStartTime, _currencyName);
      userData[msg.sender].marketsCreated++;
    }

    /**
    * @dev Creates the new market.
    * @param _marketType The type of the market.
    * @param _marketCurrencyIndex the index of market currency.
    */
    function _createMarket(uint256 _marketType, uint256 _marketCurrencyIndex, uint64 _minValue, uint64 _maxValue, uint64 _marketStartTime, bytes32 _currencyName) internal {
      require(!marketCreationPaused);
      MarketTypeData memory _marketTypeData = marketTypes[_marketType];
      address payable _market = _generateProxy(marketCurrencies[_marketCurrencyIndex].marketImplementation);
      marketData[_market].isMarket = true;
      IMarket(_market).initiate(_marketStartTime, _marketTypeData.predictionTime, _minValue, _maxValue);
      emit MarketQuestion(_market, _currencyName, _marketType, _marketStartTime);
      (marketCreationData[_marketType][_marketCurrencyIndex].penultimateMarket, marketCreationData[_marketType][_marketCurrencyIndex].marketAddress) =
       (marketCreationData[_marketType][_marketCurrencyIndex].marketAddress, _market);
    }
}