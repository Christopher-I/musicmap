oceanBounty = artifacts.require("./OceanBounty.sol");

module.exports = function(deployer) {
  deployer.deploy(oceanBounty);
};
