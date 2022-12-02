require("@nomiclabs/hardhat-waffle");
require("dotenv").config();
/** @type import('hardhat/config').HardhatUserConfig */
module.exports = {
  solidity: "0.8.1",
  abiExporter: {
    path: "./abi/pretty",
    pretty: true,
  },
  networks: {
    sepolia: {
      url: `https://sepolia.infura.io/v3/${process.env.API_KEY}`,
      accounts: [process.env.PRIVATE_KEY],
    },
  },
};
