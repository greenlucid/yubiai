# Steps to use it:

1. Define your contract in /contracts folder
2. Look at hardhat.config.ts file to check networks and compiler 
3. For each version (in case you need to adjust params in a contract for each network)
    - Create a copy in /para-deploy
4. In scripts/deploy.ts define your function to deploy your contract. There the instructions to deploy and verify