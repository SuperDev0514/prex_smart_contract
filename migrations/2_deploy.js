
const Market = artifacts.require('Market');
const MarketRegistry = artifacts.require('MarketRegistry');

module.exports = function(deployer, network, accounts){
  deployer.then(async () => {
    console.log("Deploying from " + accounts[0]);
    let marketRegistry = await deployer.deploy(MarketRegistry);
    console.log("MarketRegistry is deployed at: " + marketRegistry.address);
    let market = await deployer.deploy(Market);
    console.log("Market is deployed at: " + market.address);
    
    const date = Math.ceil(Date.now() / 1000);
    await market.initiate(date, 3600, 0, marketRegistry.address);
    //const startPrice = await market.startMarket();
    //console.log("Market is initiated with start time " + date + " and start price of ", startPrice);
  });
}