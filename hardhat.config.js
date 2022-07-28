require("@nomiclabs/hardhat-waffle");

/** @type import('hardhat/config').HardhatUserConfig */
module.exports = {
  solidity: "0.8.1",
  abiExporter: {
    path: "./abi/pretty",
    pretty: true,
  },
};
