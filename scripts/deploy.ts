// We require the Hardhat Runtime Environment explicitly here. This is optional
// but useful for running the script in a standalone fashion through `node <script>`.
//
// When running the script with `npx hardhat run <script>` you'll find the Hardhat
// Runtime Environment's members available in the global scope.
import { ethers, run } from "hardhat"

const sleep = (seconds: number): Promise<void> => {
  return new Promise((resolve) => setTimeout(resolve, seconds * 1000))
}

const SETTINGS = [
  "0x9A308aa15E7D0b92fA7BEA916230A1EC1196875e",
  3,
  259200,
  259200,
  "0x9A308aa15E7D0b92fA7BEA916230A1EC1196875e",
  0,
  60,
  20000,
  86400,
  2592000,
  86400,
  2592000
]

const GOVERNOR = "0x9A308aa15E7D0b92fA7BEA916230A1EC1196875e"
const ARBITRATOR = "0x1128eD55ab2d796fa92D2F8E1f336d745354a77A"
const EXTRA_DATA = "0x00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001"
// this needs to be changed to make it work with yubiai. pending: evidence-display
const METAEVIDENCE = "/ipfs/QmWD6CvGaXBBUwypX3vNDQ3ZQoUYqooEpccAhFHdpx2jRF/metaevidence.json"

async function main() {
  // Hardhat always runs the compile task when running scripts with its command
  // line interface.
  //
  // If this script is run directly using `node` you may want to call compile
  // manually to make sure everything is compiled
  await run("compile")

  // We get the contract to deploy
  const Yubiai = await ethers.getContractFactory("Yubiai")
  const yubiai = await Yubiai.deploy(
    SETTINGS,
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
      SETTINGS,
      GOVERNOR,
      ARBITRATOR,
      EXTRA_DATA,
      METAEVIDENCE],
  })

  // if you mess this up:
  // npx hardhat verify --network kovan DEPLOYED_CONTRACT_ADDRESS 300 {governor} "/ipfs/QmRapgPnC9HM7CueMmJhMMdrh5J9YePBn6SxmS5G3xjwcL/metaevidence.json"

  console.log("Verified in etherscan", etherscanResponse)
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error)
  process.exitCode = 1
})
