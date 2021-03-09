
pragma solidity 0.5.7;

contract IMarket {
 
  /**
    * @dev Initialize the market.
    * @param _startTime The time at which market will create.
    * @param _duration The time duration of market.
    * @param _minValue The minimum value of neutral option range.
    * @param _maxValue The maximum value of neutral option range.
    */
  function initiate(uint64 _startTime, uint64 _duration, uint64 _minValue, uint64 _maxValue, address registry) public payable;
  /**
    * @dev Place prediction on the available options of the market.
    * @param _stakeAmount The amount staked by user at the time of prediction.
    * @param _option The option on which user placed prediction.
    */
  function placePrediction(uint256 _stakeAmount, uint256 _option) public payable;
  /**
    * @dev Settle the market, setting the winning option
    */
  function endMarket() external;

  /**
    * @dev Get price of provided feed address
    **/
  function getEndingPrice() public view returns (uint256 latestAnswer, uint256 roundId);

  /**
    * @dev Claim the return amount of the specified address.
    * @param _user The address to query the claim return amount of.
    * @return Flag, if 0:cannot claim, 1: Already Claimed, 2: Claimed
    */
  function claimReturn(address payable _user) public returns(uint256);

  /**
  * @dev Gets the return amount of the specified address.
  * @param _user The address to specify the return of
  * @return returnAmount uint256 memory representing the return amount.
  */
  function getReturn(address _user) public view returns (uint256);
}