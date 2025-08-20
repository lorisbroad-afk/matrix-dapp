3x2 Matrix DApp

A decentralized application (DApp) implementing a 3x2 forced matrix system with 12-level scaling, built with Solidity smart contracts and a React Web3 frontend.

This project includes:

Fully functional smart contract with referral, earnings distribution, and level progression.

Interactive React frontend with wallet connection and matrix visualization.

Deployment scripts, testing setup, and technical documentation.

🚀 Core Features

3x2 Forced Matrix (6 positions per level, 12 levels in total)

Automated Fund Distribution with referral rewards & completion bonuses

Web3 Wallet Integration (MetaMask support)

Referral System with unique referral codes

Matrix Visualization using React & Chart.js

Security Considerations (overflow protection, access modifiers, pool redistribution)

🛠️ Tech Stack

Smart Contracts: Solidity 0.8.19

Frameworks: Truffle, OpenZeppelin

Frontend: React 18, Tailwind CSS, Web3.js

Testing: Mocha/Chai

Visualization: Chart.js

📂 Project Structure
matrix-dapp/
├── contracts/            # Solidity smart contracts
│   ├── MatrixDApp.sol
│   └── Migrations.sol
├── migrations/           # Truffle deployment scripts
├── src/                  # React frontend
│   ├── components/       # UI components
│   ├── hooks/            # Web3 hooks
│   ├── utils/            # Contract config (ABI, address)
│   ├── App.jsx
│   └── index.js
├── public/               # Static assets
├── test/                 # Contract tests
├── truffle-config.js     # Truffle network config
├── package.json
└── README.md

⚡ Smart Contract (MatrixDApp.sol)

register() → Register a new user with referral code

purchaseNextLevel() → Buy the next matrix level

distributePool() → Redistribute unclaimed funds from the pool

getUserInfo() → Fetch user details (referrals, earnings, level)

getMatrixPosition() → Get current positions in a matrix level

🖥️ Frontend (React)

Wallet Connection with MetaMask

Dashboard: Shows user level, earnings, referrals

Matrix View: Visual representation of the 3x2 slots

Level Navigation: Browse matrix levels (1–12)

🔧 Deployment
1. Smart Contract
npm install -g truffle
npm install @openzeppelin/contracts dotenv
truffle compile
truffle migrate --network testnet

2. Frontend
cd src
npm install
npm start


Update src/utils/contract.js with your deployed contract address & ABI.

Build production-ready frontend:

npm run build

🔐 Security Notes

Always test on testnets before mainnet deployment.

Implement proper owner controls.

Recommended: audit smart contracts before launch.

Use hardware wallets for sensitive operations.

📜 License

MIT License © 2025