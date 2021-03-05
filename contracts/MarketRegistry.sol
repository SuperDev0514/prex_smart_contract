
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

    struct MarketCurrency {
      address marketImplementation;
      uint8 decimals;
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
}