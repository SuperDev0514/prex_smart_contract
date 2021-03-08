
pragma solidity 0.5.7;

import "./external/openzeppelin-solidity/math/SafeMath.sol";
import "./interfaces/IToken.sol";
import "./interfaces/IMarket.sol";

contract MarketRegistry is Governed, Iupgradable {

    using SafeMath for *; 

    mapping(address => MarketData) marketData;

    address constant ETH_ADDRESS = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    address internal marketInitiater;
    address public tokenController;

    MarketCurrency[] marketCurrencies;
    MarketTypeData[] marketTypes;

    bool public marketCreationPaused;

    IToken public plotToken;
    
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