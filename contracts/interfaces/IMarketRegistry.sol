
pragma solidity 0.5.7;

contract IMarketRegistry {
  
  /**
    * @dev Register the new market
    * @param _pair The value pair of market.
    */
  function registerMarket(uint256 _pair) external returns (uint256);
  
  /**
    * @dev Get price of the specified time and pair
    * @param _time The time when to get price.
    * @param _pair The pair id which to get price.
    */
  function getPairPrice(uint256 _time, uint256 _pair) external returns (uint256);
    
  /**
  * @dev Get current time of contract
  */
  function getCurrentTime() external view returns (uint256);
}