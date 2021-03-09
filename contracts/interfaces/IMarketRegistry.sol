
pragma solidity 0.5.7;

contract IMarketRegistry {
  
  /**
  * @dev Register the new market
  */
  function registerMarket() public payable;


  function getCurrentMarket() public view returns(address);

    
}