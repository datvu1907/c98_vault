const { MerkleTree } = require("merkletreejs");
const SHA256 = require("crypto-js/sha256");

const leaves = ["a", "b", "c", "d"].map((x) => SHA256(x));
console.log(leaves);
const tree = new MerkleTree(leaves, SHA256);
const root = tree.getRoot().toString("hex");
const leaf = SHA256("b");
const proof = tree.getProof(leaf);
// console.log(tree.verify(proof, leaf, root));
// console.log(root);
