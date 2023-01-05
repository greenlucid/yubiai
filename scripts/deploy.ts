// We require the Hardhat Runtime Environment explicitly here. This is optional
// but useful for running the script in a standalone fashion through `node <script>`.
//
// When running the script with `npx hardhat run <script>` you'll find the Hardhat
// Runtime Environment's members available in the global scope.
import { ethers, run } from "hardhat"

const sleep = (seconds: number): Promise<void> => {
  return new Promise((resolve) => setTimeout(resolve, seconds * 1000))
}

const YUBIAI_SETTINGS = [
  "0x38017ec5de3f81D8B29b9260a3b64Fa7f78c039c",
  3,
  432000,
  302400,
  "0x9A308aa15E7D0b92fA7BEA916230A1EC1196875e",
  0,
  60,
  20000,
  0,
  864000,
  0,
  864000
]

const GOVERNOR = "0x38017ec5de3f81D8B29b9260a3b64Fa7f78c039c"
const ARBITRATOR = "0x08E63b61a5eC934c473346f872918775515AC450"
const EXTRA_DATA = "0x00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"
// this needs to be changed to make it work with yubiai. pending: evidence-display
const METAEVIDENCE = "/ipfs/QmWD6CvGaXBBUwypX3vNDQ3ZQoUYqooEpccAhFHdpx2jRF/metaevidence.json"

/**
 * If you need to verify, run one of the following commands
 * - npx hardhat verify --network goerli {param1} {param2} ... {paramN}
 * Ex:
 *  - npx hardhat verify --network goerli {address_deployed} 300 {governor} {metaevidence_uri}
 * 
 * Or you can pass all of the params defined in a file
 * - npx hardhat verify --network goerli --constructor-args utils/<contract>/args.js {address_deployed}
 */

async function deployYubiai() {
  // We get the contract to deploy
  const Yubiai = await ethers.getContractFactory("Yubiai")
  const yubiai = await Yubiai.deploy(
    YUBIAI_SETTINGS,
    GOVERNOR,
    ARBITRATOR,
    EXTRA_DATA,
    METAEVIDENCE
  )

  await yubiai.deployed()

  console.log("Deployed to:", yubiai.address)
  // giving time for etherscan to keep up
  await sleep(100)

  // verify in etherscan
  const etherscanResponse = await run("verify:verify", {
    address: yubiai.address,
    constructorArguments: [
      YUBIAI_SETTINGS,
      GOVERNOR,
      ARBITRATOR,
      EXTRA_DATA,
      METAEVIDENCE],
  })
  console.log("Verified in etherscan", etherscanResponse)
}

// npx hardhat verify --network goerli https://rpc.ankr.com/bsc_testnet_chapel
async function deployArbitrator() {
  // We get the contract to deploy
  const Arbitrator = await ethers.getContractFactory("Arbitrator")
  const arbitrator = await Arbitrator.deploy();
  await arbitrator.deployed()

  console.log("Deployed to:", arbitrator.address)
  // giving time for etherscan to keep up
  await sleep(100)

  // verify in etherscan
  const etherscanResponse = await run("verify:verify", {
    address: arbitrator.address,
    constructorArguments: [],
  })
  console.log("Verified in etherscan", etherscanResponse)
}

async function main() {
  // Hardhat always runs the compile task when running scripts with its command
  // line interface.
  //
  // If this script is run directly using `node` you may want to call compile
  // manually to make sure everything is compiled
  await run("compile")
  // Here the function to deploy the contract you're looking for
  deployYubiai()
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error)
  process.exitCode = 1
})
