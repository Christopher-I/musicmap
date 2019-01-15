const HDWalletProvider = require("truffle-hdwallet-provider");
module.exports = {
networks: {
  development: {
   host: "127.0.0.1",
   port: 7545,
   network_id: "*" // Match any network id
 },
 rinkeby: {
  provider: function() {
 return new HDWalletProvider("# enter mnemonic here",
  "enter infura address here")
     },
      network_id: '4',
      gas: 4500000,
      gasPrice: 10000000000,
    }
   }
 };