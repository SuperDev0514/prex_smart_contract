
pragma solidity 0.5.7;

import "./external/openzeppelin-solidity/math/SafeMath.sol";
import "./external/openzeppelin-solidity/ownership/Ownable.sol";
import "./external/openzeppelin-solidity/token/ERC20/IERC20.sol";
import "./interfaces/IToken.sol";
import "./interfaces/IMarketRegistry.sol";

contract Market is Ownable {
  using SafeMath for *;

  uint256 roundId;

  /* Market Creation Data */
  uint256 startTime;
  uint256 midTime;
  uint256 endTime;
  uint256 marketPair;

  /* Market Live Data */
  uint256 startPrice;
  uint256 totalUsers;
  uint256 totalStaked;
  uint256 totalCommission;

  /* Market Result Data */
  uint256 endPrice;
  uint256 totalReward;
  uint256 winningOption;

  /* Constants */
  uint256 constant minStakeAmount = 1;
  uint256 constant commissionPerc = 10; //with 2 decimals

  /* External assets */
  address constant ETH_ADDRESS = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
  address constant ASSET_ADDRESS = 0x4F96Fe3b7A6Cf9725f59d353F723c1bDb64CA6Aa;
  IMarketRegistry marketRegistry;
  IERC20 assetToken = IERC20(ASSET_ADDRESS);
  
  /* Predicting users */
  struct UserData {
    mapping(uint256 => uint256) assetStaked;
    bool available;
    bool claimedReward;
    uint256 returnAmount;
  }
  mapping(address => UserData) internal userData;
  mapping(uint256 => address) internal users;
  
  /* Predicting options */
  enum Option {
    Bullish,
    Bearish
  }
  mapping(uint256 => uint256) internal optionStaked;
  uint256 constant optionCnt = 2;

  /**
    * @dev Initialize the market.
    * @param _startTime The time at which market will create.
    * @param _duration The time duration of market.
    * @param _marketPair The value pair of market.
    * @param registry The address of market registry.
    */
  function initiate(uint256 _startTime, uint256 _duration, uint256 _marketPair, address registry) external onlyOwner {
    require(startTime == 0, "Already initialized");
    require(_startTime.add(_duration) > block.timestamp);

    startTime = _startTime;
    midTime = _startTime.add(_duration);
    endTime = midTime.add(_duration);
    marketPair = _marketPair;
    marketRegistry = IMarketRegistry(registry);

    winningOption = optionCnt;
    marketRegistry.registerMarket();
  }
  
  /**
    * @dev Start market
    */
  function startMarket() external onlyOwner returns (uint256 _roundId, uint256 _startPrice) {
    require(startPrice == 0, "Market already started");
    require(startTime <= block.timestamp, "It's not yet start time");

    startPrice = marketRegistry.getPairPrice(startTime, marketPair);
    emit MarketStarted(startPrice);
    _roundId = roundId;
    _startPrice = startPrice;
  }

  /**
    * @dev Place prediction on the available options of the market.
    * @param _stakeAmount The amount staked by user at the time of prediction.
    * @param _option The option on which user placed prediction.
    */
  function placePrediction(uint256 _stakeAmount, uint256 _option) external payable {
    require(_option < optionCnt, "Option is invalid");
    require(block.timestamp >= startTime, "Market has not started yet");
    require(block.timestamp <= midTime, "Market prediction has expried.");
    require(msg.value == 0, "Not allowed transaction value.");

    assetToken.transferFrom(msg.sender, address(this), _stakeAmount);
    uint256 commissionAmount = _calculatePercentage(commissionPerc, _stakeAmount, 10000);
    uint256 realAmount = _stakeAmount.sub(commissionAmount);

    require(realAmount > minStakeAmount, "Too small amount");
    totalCommission = totalCommission.add(commissionAmount);
    _storePredictionData(realAmount, _option);

    uint256[] memory _optionStaked = new uint256[](optionCnt);
    for (uint256 i = 0; i < optionCnt; i++) {
      _optionStaked[i] = optionStaked[i];
    }

    emit PredictionDataUpdated(totalUsers, totalStaked, _optionStaked);
  }
    
  /**
    * @dev Stores the prediction data.
    * @param _stakeAmount The amount staked by user at the time of prediction.
    * @param _option The option on which user place prediction.
    */
  function _storePredictionData(uint256 _stakeAmount, uint256 _option) internal {
    if (userData[msg.sender].available == false) {
      userData[msg.sender].available = true;
      users[totalUsers] = msg.sender;
      totalUsers++;
    }
    userData[msg.sender].assetStaked[_option] = userData[msg.sender].assetStaked[_option].add(_stakeAmount);
    optionStaked[_option] = optionStaked[_option].add(_stakeAmount);
    totalStaked = totalStaked.add(_stakeAmount);
  }
  
  /**
    * @dev Settle the market, setting the winning option
    */
  function endMarket() external onlyOwner returns(uint256 _endPrice) {
    require(endTime < block.timestamp, "Market has not ended yet.");
    endPrice = marketRegistry.getPairPrice(endTime, marketPair);
    _postResult();
    emit MarketEnded(endPrice, winningOption);
    _endPrice = endPrice;
  }

  /**
    * @dev Calculate the result of market.
    */
  function _postResult() internal {
    
    uint256 i;

    if(endPrice >= startPrice) {
      winningOption = uint256(Option.Bullish);
    } else {
      winningOption = uint256(Option.Bearish);
    }
    if (optionStaked[winningOption] > 0) {
      totalReward = totalStaked;
    }
    for (i = 0; i < totalUsers; i++) {
      claimReturn(users[i]);
    }
  }

  /**
    * @dev Claim the return amount of the specified address.
    * @param _user The address to query the claim return amount of.
    * @return Flag, if 0:cannot claim, 1: Already Claimed, 2: Claimed
    */
  function claimReturn(address _user) public returns(uint256) {

    if(userData[_user].claimedReward) {
      return 1;
    }
    userData[_user].claimedReward = true;
    uint256 _returnAmount = getReturn(_user);
    if (_returnAmount > 0) {
      _transferAsset(ASSET_ADDRESS, address(uint160(_user)), _returnAmount);
    }
    userData[_user].returnAmount = _returnAmount;
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
  * @dev Gets the return amount of the specified address.
  * @param _user The address to specify the return of
  * @return returnAmount uint256 memory representing the return amount.
  */
  function getReturn(address _user) public view returns (uint256) {
    if (optionStaked[winningOption] == 0) {
      return 0;
    }
    else {
      return userData[_user].assetStaked[winningOption].mul(totalReward).div(optionStaked[winningOption]);
    }
  }

  /**
  * @dev Gets the market data.
  */
  function getMarketData() public view 
    returns (
      uint256 _startTime, uint256 _midTime, uint256 _endTime, uint256 _marketPair,
      uint256 _startPrice, uint256 _endPrice,
      uint256 _totalUsers, uint256 _totalStaked, 
      uint256 _totalReward, uint256 _winningOption
    ) {
    _startTime = startTime;
    _midTime = midTime;
    _endTime = endTime;
    _marketPair = marketPair;
    _startPrice = startPrice;
    _endPrice = endPrice;
    _totalUsers = totalUsers;
    _totalStaked = totalStaked;
    _totalReward = totalReward;
    _winningOption = winningOption;
  }

  /**
  * @dev Gets the prediction data.
  */
  function getPredictionData() public view returns (uint256 _totalUsers, uint256[] memory _totalStaked, uint256[] memory _userStaked) {
    _totalStaked = new uint256[](optionCnt);
    _userStaked = new uint256[](optionCnt);
    _totalUsers = totalUsers;
    uint256 i;
    for(i = 0; i < optionCnt; i++) {
      _totalStaked[i] = optionStaked[i];
      if (userData[msg.sender].available)
        _userStaked[i] = userData[msg.sender].assetStaked[i];
    }
  }

  function _calculatePercentage(uint256 _percent, uint256 _value, uint256 _divisor) internal pure returns(uint256) {
    return _percent.mul(_value).div(_divisor);
  }

  event MarketStarted (
    uint256 startPrice
  );

  event PredictionDataUpdated (
    uint256 totalUsers,
    uint256 totalStaked,
    uint256[] optionStaked
  );

  event MarketEnded (
    uint256 endPrice,
    uint256 winningOption
  );
}