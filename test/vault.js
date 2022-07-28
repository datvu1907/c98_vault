const { MerkleTree } = require("merkletreejs");

const { ethers, waffle } = require("hardhat");
const { expect } = require("chai");
const { time } = require("@openzeppelin/test-helpers");
const keccak256 = require("keccak256");
const web3 = require("web3-utils");

const provider = waffle.provider;

function Schedule(index, user, recieveTokenId, sendingAmount) {
  this.index = index;
  this.user = user;
  this.recieveTokenId = recieveTokenId;
  this.sendingAmount = sendingAmount;
}
async function increaseTime(duration) {
  await provider.send("evm_increaseTime", [duration]);
  await provider.send("evm_mine");
}
let admin;
let user1;
let user2;
let user3;
let user4;
let user5;
let user6;
let user7;
let user8;

let nft721;
let nft1155;
let erc20token;
let vault;
let vaultFactory;
let listSchedule;
beforeEach(async function () {
  [admin, user1, user2, user3, user4, user5, user6, user7, user8] =
    await ethers.getSigners();

  const NFT721 = await ethers.getContractFactory("NFT721", admin);
  nft721 = await NFT721.deploy();
  const NFT1155 = await ethers.getContractFactory("NFT1155", admin);
  nft1155 = await NFT1155.deploy();

  const ERC20Token = await ethers.getContractFactory("ERC20Token", admin);
  erc20token = await ERC20Token.deploy();

  const Vault = await ethers.getContractFactory("Coin98Vault", admin);
  vault = await Vault.deploy();
  const VaultFactory = await ethers.getContractFactory(
    "Coin98VaultFactory",
    admin
  );
  vaultFactory = await VaultFactory.deploy(vault.address);

  listSchedule = [
    new Schedule(1, user1.address, 1, 120),
    new Schedule(2, user2.address, 2, 120),
    new Schedule(3, user3.address, 3, 120),
    new Schedule(4, user4.address, 4, 120),
    new Schedule(5, user5.address, 5, 120),
    new Schedule(6, user6.address, 6, 120),
    new Schedule(7, user7.address, 7, 120),
    new Schedule(8, user8.address, 8, 120),
  ];
  await erc20token.connect(admin).mint(user1.address, 1000);
});
describe("C98 vault", function () {
  it("Factory create vault and redeem 1155", async function () {
    await vaultFactory.connect(admin).setImplementation(vault.address);
    expect(await vaultFactory.connect(admin).getImplementation()).to.equals(
      vault.address
    );

    const newVaultAddress = await vaultFactory
      .connect(admin)
      .createVault(
        admin.address,
        "0xd4967590eb024589dfb6b9e48a576eb49ebc19d764b0d1d67dc21975e7258e97"
      );

    const receipt = await newVaultAddress.wait();

    expect(await erc20token.connect(admin).balanceOf(user1.address)).to.equals(
      1000
    );

    const leaves = listSchedule.map((item) =>
      web3.soliditySha3(
        item.index,
        item.user,
        item.recieveTokenId,
        item.sendingAmount
      )
    );
    const tree = new MerkleTree(leaves, keccak256, { sort: true });
    const root = tree.getHexRoot();

    const leaf = web3.soliditySha3(1, user1.address, 1, 120);
    const proof = tree.getHexProof(leaf);

    const proofArray = proof.map((item) => item);
    console.log(root);
    console.log(leaf);
    console.log(proofArray);

    console.log(tree.verify(proof, leaf, root));

    const NewVault = await ethers.getContractFactory("Coin98Vault");
    const newVault = NewVault.attach(receipt.logs[0].address);

    await newVault
      .connect(admin)
      .createEvent(1, Date.now(), root, nft1155.address, erc20token.address);
    await newVault.connect(admin).setEventStatus(1, 1);
    await nft1155.connect(admin).mint(receipt.logs[0].address, 1, 100, "0x");
    await erc20token.connect(user1).approve(receipt.logs[0].address, 200);
    await increaseTime(Date.now() + 3600);
    await newVault
      .connect(user1)
      .redeemERC1155(1, 1, user1.address, 1, 120, proof);

    // check amount nft of user
    expect(await nft1155.connect(admin).balanceOf(user1.address, 1)).to.equals(
      1
    );
    // check amount of token in vault
    expect(
      await erc20token.connect(admin).balanceOf(receipt.logs[0].address)
    ).to.equals(120);
  });
  it("Factory create vault and redeem 721", async function () {
    await vaultFactory.connect(admin).setImplementation(vault.address);
    expect(await vaultFactory.connect(admin).getImplementation()).to.equals(
      vault.address
    );

    const newVaultAddress = await vaultFactory
      .connect(admin)
      .createVault(
        admin.address,
        "0xd4967590eb024589dfb6b9e48a576eb49ebc19d764b0d1d67dc21975e7258e97"
      );

    const receipt = await newVaultAddress.wait();

    expect(await erc20token.connect(admin).balanceOf(user1.address)).to.equals(
      1000
    );

    const leaves = listSchedule.map((item) =>
      web3.soliditySha3(
        item.index,
        item.user,
        item.recieveTokenId,
        item.sendingAmount
      )
    );
    const tree = new MerkleTree(leaves, keccak256, { sort: true });
    const root = tree.getHexRoot();

    const leaf = web3.soliditySha3(1, user1.address, 1, 120);
    const proof = tree.getHexProof(leaf);

    console.log(tree.verify(proof, leaf, root));

    const NewVault = await ethers.getContractFactory("Coin98Vault");
    const newVault = NewVault.attach(receipt.logs[0].address);

    await newVault
      .connect(admin)
      .createEvent(1, Date.now(), root, nft721.address, erc20token.address);
    await newVault.connect(admin).setEventStatus(1, 1);
    await nft721.connect(admin).mint(receipt.logs[0].address, 1);
    await erc20token.connect(user1).approve(receipt.logs[0].address, 200);
    await increaseTime(Date.now() + 3600);
    await newVault
      .connect(user1)
      .redeemERC721(1, 1, user1.address, 1, 120, proof);
    // check amount nft of user
    expect(await nft721.connect(admin).balanceOf(user1.address)).to.equals(1);
    // check amount of token in vault
    expect(
      await erc20token.connect(admin).balanceOf(receipt.logs[0].address)
    ).to.equals(120);
  });
});
