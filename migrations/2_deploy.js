
const Market = artifacts.require('Market');
const MarketRegistry = artifacts.require('MarketRegistry');

module.exports = function(deployer, network, accounts){
  deployer.then(async () => {
    let marketRegistry = await deployer.deploy(MarketRegistry);
    console.log("MarketRegistry is deployed at: " + marketRegistry.address);
    let market = await deployer.deploy(Market);
    console.log("Market is deployed at: " + market.address);
    const date = Date.now();
    await market.initiate(date, 3600000, 1700, 2000, marketRegistry.address);
    console.log("Market is initiated with start time " + date);
  });
}