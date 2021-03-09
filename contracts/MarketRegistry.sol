
pragma solidity 0.5.7;

import "./external/openzeppelin-solidity/math/SafeMath.sol";
import "./interfaces/IToken.sol";
import "./interfaces/IMarket.sol";
import "./external/openzeppelin-solidity/ownership/Ownable.sol";

contract MarketRegistry is Ownable {

  using SafeMath for *; 

  mapping(uint => address) markets;
  uint totalMarkets;
  
  /**
  * @dev Register the new market
  */
  function registerMarket() public payable {
    markets[totalMarkets] = msg.sender;
    totalMarkets++;
  }


  function getCurrentMarket() public view returns(address) {
    require(totalMarkets != 0, "No market");
    return markets[totalMarkets - 1];
  }

    
}