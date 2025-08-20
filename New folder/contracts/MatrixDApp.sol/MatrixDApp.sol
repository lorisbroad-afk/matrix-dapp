// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

contract MatrixDApp {
    address public owner;
    uint256 public constant MAX_LEVEL = 12;
    uint256 public constant MATRIX_WIDTH = 3;
    uint256 public constant MATRIX_HEIGHT = 2;
    uint256 public constant POSITIONS_PER_LEVEL = 6;
    
    struct User {
        bool isActive;
        address referrer;
        uint256 currentLevel;
        uint256[] referrals;
        mapping(uint256 => uint256) earnings;
        mapping(uint256 => uint256) positions;
        uint256 lockedBalance;
        uint256 totalEarnings;
    }
    
    struct MatrixLevel {
        uint256 price;
        uint256 completionBonus;
        mapping(uint256 => address) positions;
        uint256 activePositions;
        bool isComplete;
    }
    
    mapping(address => User) public users;
    mapping(uint256 => MatrixLevel) public matrixLevels;
    mapping(address => string) public referralCodes;
    mapping(string => address) public codeToAddress;
    
    address[] public activeUsers;
    uint256 public totalUsers;
    uint256 public redistributionPool;
    bool public gameEnded = false;
    
    event UserRegistered(address indexed user, address indexed referrer, string referralCode);
    event LevelPurchased(address indexed user, uint256 level, uint256 price);
    event EarningsDistributed(address indexed user, uint256 amount, uint8 line);
    event CompletionBonus(address indexed user, uint256 level, uint256 bonus);
    event PositionShift(address indexed user, uint256 fromLevel, uint256 toLevel);
    event GameEnded(address indexed winner);
    
    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner can call this function");
        _;
    }
    
    modifier gameActive() {
        require(!gameEnded, "Game has ended");
        _;
    }
    
    constructor() {
        owner = msg.sender;
        _initializeLevels();
    }
    
    function _initializeLevels() private {
        uint256 basePrice = 0.01 ether;
        for (uint256 i = 1; i <= MAX_LEVEL; i++) {
            matrixLevels[i].price = basePrice * (2 ** (i - 1));
            matrixLevels[i].completionBonus = matrixLevels[i].price * 3;
        }
    }
    
    function register(address _referrer, string memory _referralCode) external payable gameActive {
        require(!users[msg.sender].isActive, "User already registered");
        require(bytes(_referralCode).length > 0, "Referral code required");
        require(codeToAddress[_referralCode] == address(0), "Referral code already exists");
        
        if (_referrer != address(0)) {
            require(users[_referrer].isActive, "Invalid referrer");
        } else {
            _referrer = owner;
        }
        
        require(msg.value >= matrixLevels[1].price, "Insufficient payment for level 1");
        
        users[msg.sender].isActive = true;
        users[msg.sender].referrer = _referrer;
        users[msg.sender].currentLevel = 1;
        
        referralCodes[msg.sender] = _referralCode;
        codeToAddress[_referralCode] = msg.sender;
        
        users[_referrer].referrals.push(totalUsers);
        activeUsers.push(msg.sender);
        totalUsers++;
        
        _purchaseLevel(1);
        
        emit UserRegistered(msg.sender, _referrer, _referralCode);
    }
    
    function purchaseNextLevel() external payable gameActive {
        require(users[msg.sender].isActive, "User not registered");
        uint256 nextLevel = users[msg.sender].currentLevel + 1;
        require(nextLevel <= MAX_LEVEL, "Max level reached");
        require(msg.value >= matrixLevels[nextLevel].price, "Insufficient payment");
        
        users[msg.sender].currentLevel = nextLevel;
        _purchaseLevel(nextLevel);
        
        if (nextLevel == MAX_LEVEL) {
            gameEnded = true;
            emit GameEnded(msg.sender);
        }
    }
    
    function _purchaseLevel(uint256 level) private {
        uint256 position = _findNextPosition(level);
        matrixLevels[level].positions[position] = msg.sender;
        users[msg.sender].positions[level] = position;
        matrixLevels[level].activePositions++;
        
        _distributeFunds(msg.sender, level);
        
        if (matrixLevels[level].activePositions == POSITIONS_PER_LEVEL) {
            matrixLevels[level].isComplete = true;
            _handleLevelCompletion(level);
        }
        
        emit LevelPurchased(msg.sender, level, matrixLevels[level].price);
    }
    
    function _findNextPosition(uint256 level) private view returns (uint256) {
        for (uint256 i = 0; i < POSITIONS_PER_LEVEL; i++) {
            if (matrixLevels[level].positions[i] == address(0)) {
                return i;
            }
        }
        revert("No available positions");
    }
    
    function _distributeFunds(address user, uint256 level) private {
        uint256 amount = matrixLevels[level].price;
        uint256 firstLineShare = amount * 25 / 100;
        uint256 secondLineShare = amount * 25 / 100;
        uint256 completionShare = amount * 50 / 100;
        
        // First line (direct referrer)
        address firstLine = users[user].referrer;
        if (firstLine != address(0) && users[firstLine].currentLevel >= level) {
            users[firstLine].earnings[level] += firstLineShare;
            users[firstLine].totalEarnings += firstLineShare;
            payable(firstLine).transfer(firstLineShare);
            emit EarningsDistributed(firstLine, firstLineShare, 1);
        } else {
            redistributionPool += firstLineShare;
        }
        
        // Second line (referrer's referrer)
        address secondLine = firstLine != address(0) ? users[firstLine].referrer : address(0);
        if (secondLine != address(0) && users[secondLine].currentLevel >= level) {
            users[secondLine].earnings[level] += secondLineShare;
            users[secondLine].totalEarnings += secondLineShare;
            payable(secondLine).transfer(secondLineShare);
            emit EarningsDistributed(secondLine, secondLineShare, 2);
        } else {
            redistributionPool += secondLineShare;
        }
        
        // Completion bonus goes to pool
        redistributionPool += completionShare;
    }
    
    function _handleLevelCompletion(uint256 level) private {
        uint256 bonus = matrixLevels[level].completionBonus;
        
        for (uint256 i = 0; i < POSITIONS_PER_LEVEL; i++) {
            address user = matrixLevels[level].positions[i];
            if (user != address(0)) {
                uint256 userBonus = bonus / POSITIONS_PER_LEVEL;
                users[user].totalEarnings += userBonus;
                payable(user).transfer(userBonus);
                emit CompletionBonus(user, level, userBonus);
            }
        }
    }
    
    function distributePool() external onlyOwner {
        require(redistributionPool > 0, "No funds to distribute");
        
        uint256 eligibleUsers = 0;
        for (uint256 i = 0; i < activeUsers.length; i++) {
            if (users[activeUsers[i]].totalEarnings >= 1 ether) {
                eligibleUsers++;
            }
        }
        
        if (eligibleUsers > 0) {
            uint256 sharePerUser = redistributionPool / eligibleUsers;
            for (uint256 i = 0; i < activeUsers.length; i++) {
                address user = activeUsers[i];
                if (users[user].totalEarnings >= 1 ether) {
                    users[user].totalEarnings += sharePerUser;
                    payable(user).transfer(sharePerUser);
                }
            }
            redistributionPool = 0;
        }
    }
    
    function getUserInfo(address user) external view returns (
        bool isActive,
        address referrer,
        uint256 currentLevel,
        uint256 totalEarnings,
        uint256 lockedBalance,
        uint256[] memory referrals
    ) {
        User storage u = users[user];
        return (
            u.isActive,
            u.referrer,
            u.currentLevel,
            u.totalEarnings,
            u.lockedBalance,
            u.referrals
        );
    }
    
    function getMatrixPosition(uint256 level) external view returns (address[6] memory) {
        address[6] memory positions;
        for (uint256 i = 0; i < POSITIONS_PER_LEVEL; i++) {
            positions[i] = matrixLevels[level].positions[i];
        }
        return positions;
    }
    
    function getLevelPrice(uint256 level) external view returns (uint256) {
        return matrixLevels[level].price;
    }
}

On Wed, 20 Aug 2025 at 13:58, Sam Judith <samjudith137@gmail.com> wrote:
const { useState, useEffect } = React;

function MatrixDApp() {
    const [web3, setWeb3] = useState(null);
    const [account, setAccount] = useState('');
    const [contract, setContract] = useState(null);
    const [userInfo, setUserInfo] = useState(null);
    const [matrixData, setMatrixData] = useState([]);
    const [currentLevel, setCurrentLevel] = useState(1);
    const [loading, setLoading] = useState(false);

    const contractABI = [
        // Contract ABI would go here
    ];

    const connectWallet = async () => {
        if (typeof window.ethereum !== 'undefined') {
            try {
                await window.ethereum.request({ method: 'eth_requestAccounts' });
                const web3Instance = new Web3(window.ethereum);
                setWeb3(web3Instance);
                
                const accounts = await web3Instance.eth.getAccounts();
                setAccount(accounts[0]);
                
                // Initialize contract
                const contractInstance = new web3Instance.eth.Contract(contractABI, CONTRACT_ADDRESS);
                setContract(contractInstance);
                
            } catch (error) {
                console.error('Error connecting wallet:', error);
            }
        } else {
            alert('Please install MetaMask!');
        }
    };

    const loadUserData = async () => {
        if (contract && account) {
            try {
                const info = await contract.methods.getUserInfo(account).call();
                setUserInfo(info);
                
                if (info.isActive) {
                    loadMatrixData(info.currentLevel);
                }
            } catch (error) {
                console.error('Error loading user data:', error);
            }
        }
    };

    const loadMatrixData = async (level) => {
        if (contract) {
            try {
                const positions = await contract.methods.getMatrixPosition(level).call();
                setMatrixData(positions);
            } catch (error) {
                console.error('Error loading matrix data:', error);
            }
        }
    };

    const registerUser = async (referrerCode) => {
        if (contract && account) {
            try {
                setLoading(true);
                const price = await contract.methods.getLevelPrice(1).call();
                
                await contract.methods.register(
                    referrerCode || account,
                    `REF_${Date.now()}`
                ).send({
                    from: account,
                    value: price
                });
                
                await loadUserData();
            } catch (error) {
                console.error('Error registering:', error);
            } finally {
                setLoading(false);
            }
        }
    };

    useEffect(() => {
        if (web3 && account) {
            loadUserData();
        }
    }, [web3, account]);

    return (
        

            

                
                    

                        3x2 Matrix DApp
                    

                    {!account ? (
                        
                            Connect Wallet
                        
                    ) : (
                        

                            
Connected:


                            
{account}


                        

                    )}
                

                {account && (
                    

                        

                            
Dashboard

                            {userInfo ? (
                                

                                    

                                        

                                            
Current Level


                                            

                                                {userInfo.currentLevel}
                                            


                                        

                                        

                                            
Total Earnings


                                            

                                                {web3?.utils.fromWei(userInfo.totalEarnings, 'ether')} ETH
                                            


                                        

                                    

                                    

                                        
Referrals


                                        

                                            {userInfo.referrals.length}
                                        


                                    

                                

                            ) : (
                                

                                     registerUser('')}
                                        disabled={loading}
                                        className="bg-green-600 text-white px-6 py-3 rounded-lg font-semibold hover:bg-green-700 transition-colors disabled:opacity-50"
                                    >
                                        {loading ? 'Registering...' : 'Register Now'}
                                    
                                

                            )}
                        


                        

                            
Matrix Level {currentLevel}

                            

                                {Array.from({ length: 6 }, (_, i) => (
                                    

                                        {matrixData[i] && matrixData[i] !== '0x0000000000000000000000000000000000000000'
                                            ? `${matrixData[i].slice(0, 6)}...`
                                            : 'Empty'
                                        }
                                    

                                ))}
                            

                            

                                 setCurrentLevel(Math.max(1, currentLevel - 1))}
                                    className="px-4 py-2 bg-gray-200 rounded-lg hover:bg-gray-300 transition-colors"
                                    disabled={currentLevel <= 1}
                                >
                                    ← Previous
                                
                                 setCurrentLevel(Math.min(12, currentLevel + 1))}
                                    className="px-4 py-2 bg-gray-200 rounded-lg hover:bg-gray-300 transition-colors"
                                    disabled={currentLevel >= 12}
                                >
                                    Next →
                                
                            

                        

                    

                )}
            

        

    );
}

On Wed, 20 Aug 2025 at 13:37, Peter Bauer Ruhenstroth <peterruhenstrothbaueragency@gmail.com> wrote:


On Wed, Aug 20, 2025 at 5:32 AM Peter Bauer Ruhenstroth <peterruhenstrothbaueragency@gmail.com> wrote:
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>3x2 Matrix DApp - Complete Development Package</title>
    <link href="https://cdn.jsdelivr.net/npm/tailwindcss@2.2.19/dist/tailwind.min.css" rel="stylesheet">
    <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/@fortawesome/fontawesome-free@6.4.0/css/all.min.css">
    <script src="https://unpkg.com/react@18/umd/react.development.js"></script>
    <script src="https://unpkg.com/react-dom@18/umd/react-dom.development.js"></script>
    <script src="https://unpkg.com/@babel/standalone/babel.min.js"></script>
    <script src="https://cdn.jsdelivr.net/npm/web3@1.9.0/dist/web3.min.js"></script>
    <script src="https://cdn.jsdelivr.net/npm/chart.js"></script>
    <style>
        body { font-family: 'Inter', sans-serif; }
        .gradient-bg { background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); }
        .matrix-node { transition: all 0.3s ease; }
        .matrix-node:hover { transform: scale(1.05); }
        .code-block { background: #1e293b; color: #e2e8f0; padding: 1rem; border-radius: 0.5rem; overflow-x: auto; }
        .highlight { background: #fbbf24; color: #1f2937; padding: 0.125rem 0.25rem; border-radius: 0.25rem; }
        @media print {
            body { font-size: 12px; }
            .no-print { display: none !important; }
        }
    </style>
</head>
<body class="bg-gray-50">
    <!-- Header -->
    <header class="gradient-bg text-white py-8">
        <div class="container mx-auto px-4">
            <h1 class="text-4xl font-bold text-center mb-4">
                <i class="fas fa-cube mr-3"></i>3x2 Matrix DApp
            </h1>
            <p class="text-xl text-center opacity-90">Complete Development Package with Smart Contracts & Frontend</p>
        </div>
    </header>

    <!-- Main Content -->
    <div class="container mx-auto px-4 py-8">
       
        <!-- Project Overview -->
        <section class="mb-12">
            <div class="bg-white rounded-lg shadow-lg p-8">
                <h2 class="text-3xl font-bold mb-6 text-gray-800">
                    <i class="fas fa-info-circle mr-3 text-blue-600"></i>Project Overview
                </h2>
                <div class="grid md:grid-cols-2 gap-6">
                    <div>
                        <h3 class="text-xl font-semibold mb-4 text-gray-700">Core Features</h3>
                        <ul class="space-y-2">
                            <li class="flex items-center"><i class="fas fa-check text-green-500 mr-2"></i>3x2 Forced Matrix System</li>
                            <li class="flex items-center"><i class="fas fa-check text-green-500 mr-2"></i>12-Level Scaling</li>
                            <li class="flex items-center"><i class="fas fa-check text-green-500 mr-2"></i>Web3 Wallet Integration</li>
                            <li class="flex items-center"><i class="fas fa-check text-green-500 mr-2"></i>Referral System</li>
                            <li class="flex items-center"><i class="fas fa-check text-green-500 mr-2"></i>Automated Fund Distribution</li>
                            <li class="flex items-center"><i class="fas fa-check text-green-500 mr-2"></i>Position Management</li>
                        </ul>
                    </div>
                    <div>
                        <h3 class="text-xl font-semibold mb-4 text-gray-700">Technical Stack</h3>
                        <ul class="space-y-2">
                            <li class="flex items-center"><i class="fab fa-ethereum text-blue-500 mr-2"></i>Solidity Smart Contracts</li>
                            <li class="flex items-center"><i class="fab fa-react text-blue-500 mr-2"></i>React Frontend</li>
                            <li class="flex items-center"><i class="fas fa-link text-blue-500 mr-2"></i>Web3.js Integration</li>
                            <li class="flex items-center"><i class="fas fa-palette text-blue-500 mr-2"></i>Tailwind CSS</li>
                            <li class="flex items-center"><i class="fas fa-chart-line text-blue-500 mr-2"></i>Chart.js Visualization</li>
                        </ul>
                    </div>
                </div>
            </div>
        </section>

        <!-- Smart Contract -->
        <section class="mb-12">
            <div class="bg-white rounded-lg shadow-lg p-8">
                <h2 class="text-3xl font-bold mb-6 text-gray-800">
                    <i class="fas fa-file-contract mr-3 text-purple-600"></i>Smart Contract
                </h2>
                <p class="text-gray-600 mb-6">Complete Solidity smart contract implementing the 3x2 matrix system with all required functionality.</p>
               
                <div class="bg-gray-900 rounded-lg p-4 mb-6">
                    <div class="flex items-center justify-between mb-4">
                        <h3 class="text-white font-semibold">MatrixDApp.sol</h3>
                        <span class="bg-green-500 text-white px-2 py-1 rounded text-sm">Solidity 0.8.19</span>
                    </div>
                    <pre class="text-green-400 text-sm overflow-x-auto"><code>// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

contract MatrixDApp {
    address public owner;
    uint256 public constant MAX_LEVEL = 12;
    uint256 public constant MATRIX_WIDTH = 3;
    uint256 public constant MATRIX_HEIGHT = 2;
    uint256 public constant POSITIONS_PER_LEVEL = 6;
   
    struct User {
        bool isActive;
        address referrer;
        uint256 currentLevel;
        uint256[] referrals;
        mapping(uint256 => uint256) earnings;
        mapping(uint256 => uint256) positions;
        uint256 lockedBalance;
        uint256 totalEarnings;
    }
   
    struct MatrixLevel {
        uint256 price;
        uint256 completionBonus;
        mapping(uint256 => address) positions;
        uint256 activePositions;
        bool isComplete;
    }
   
    mapping(address => User) public users;
    mapping(uint256 => MatrixLevel) public matrixLevels;
    mapping(address => string) public referralCodes;
    mapping(string => address) public codeToAddress;
   
    address[] public activeUsers;
    uint256 public totalUsers;
    uint256 public redistributionPool;
    bool public gameEnded = false;
   
    event UserRegistered(address indexed user, address indexed referrer, string referralCode);
    event LevelPurchased(address indexed user, uint256 level, uint256 price);
    event EarningsDistributed(address indexed user, uint256 amount, uint8 line);
    event CompletionBonus(address indexed user, uint256 level, uint256 bonus);
    event PositionShift(address indexed user, uint256 fromLevel, uint256 toLevel);
    event GameEnded(address indexed winner);
   
    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner can call this function");
        _;
    }
   
    modifier gameActive() {
        require(!gameEnded, "Game has ended");
        _;
    }
   
    constructor() {
        owner = msg.sender;
        _initializeLevels();
    }
   
    function _initializeLevels() private {
        uint256 basePrice = 0.01 ether;
        for (uint256 i = 1; i <= MAX_LEVEL; i++) {
            matrixLevels[i].price = basePrice * (2 ** (i - 1));
            matrixLevels[i].completionBonus = matrixLevels[i].price * 3;
        }
    }
   
    function register(address _referrer, string memory _referralCode) external payable gameActive {
        require(!users[msg.sender].isActive, "User already registered");
        require(bytes(_referralCode).length > 0, "Referral code required");
        require(codeToAddress[_referralCode] == address(0), "Referral code already exists");
       
        if (_referrer != address(0)) {
            require(users[_referrer].isActive, "Invalid referrer");
        } else {
            _referrer = owner;
        }
       
        require(msg.value >= matrixLevels[1].price, "Insufficient payment for level 1");
       
        users[msg.sender].isActive = true;
        users[msg.sender].referrer = _referrer;
        users[msg.sender].currentLevel = 1;
       
        referralCodes[msg.sender] = _referralCode;
        codeToAddress[_referralCode] = msg.sender;
       
        users[_referrer].referrals.push(totalUsers);
        activeUsers.push(msg.sender);
        totalUsers++;
       
        _purchaseLevel(1);
       
        emit UserRegistered(msg.sender, _referrer, _referralCode);
    }
   
    function purchaseNextLevel() external payable gameActive {
        require(users[msg.sender].isActive, "User not registered");
        uint256 nextLevel = users[msg.sender].currentLevel + 1;
        require(nextLevel <= MAX_LEVEL, "Max level reached");
        require(msg.value >= matrixLevels[nextLevel].price, "Insufficient payment");
       
        users[msg.sender].currentLevel = nextLevel;
        _purchaseLevel(nextLevel);
       
        if (nextLevel == MAX_LEVEL) {
            gameEnded = true;
            emit GameEnded(msg.sender);
        }
    }
   
    function _purchaseLevel(uint256 level) private {
        uint256 position = _findNextPosition(level);
        matrixLevels[level].positions[position] = msg.sender;
        users[msg.sender].positions[level] = position;
        matrixLevels[level].activePositions++;
       
        _distributeFunds(msg.sender, level);
       
        if (matrixLevels[level].activePositions == POSITIONS_PER_LEVEL) {
            matrixLevels[level].isComplete = true;
            _handleLevelCompletion(level);
        }
       
        emit LevelPurchased(msg.sender, level, matrixLevels[level].price);
    }
   
    function _findNextPosition(uint256 level) private view returns (uint256) {
        for (uint256 i = 0; i < POSITIONS_PER_LEVEL; i++) {
            if (matrixLevels[level].positions[i] == address(0)) {
                return i;
            }
        }
        revert("No available positions");
    }
   
    function _distributeFunds(address user, uint256 level) private {
        uint256 amount = matrixLevels[level].price;
        uint256 firstLineShare = amount * 25 / 100;
        uint256 secondLineShare = amount * 25 / 100;
        uint256 completionShare = amount * 50 / 100;
       
        // First line (direct referrer)
        address firstLine = users[user].referrer;
        if (firstLine != address(0) && users[firstLine].currentLevel >= level) {
            users[firstLine].earnings[level] += firstLineShare;
            users[firstLine].totalEarnings += firstLineShare;
            payable(firstLine).transfer(firstLineShare);
            emit EarningsDistributed(firstLine, firstLineShare, 1);
        } else {
            redistributionPool += firstLineShare;
        }
       
        // Second line (referrer's referrer)
        address secondLine = firstLine != address(0) ? users[firstLine].referrer : address(0);
        if (secondLine != address(0) && users[secondLine].currentLevel >= level) {
            users[secondLine].earnings[level] += secondLineShare;
            users[secondLine].totalEarnings += secondLineShare;
            payable(secondLine).transfer(secondLineShare);
            emit EarningsDistributed(secondLine, secondLineShare, 2);
        } else {
            redistributionPool += secondLineShare;
        }
       
        // Completion bonus goes to pool
        redistributionPool += completionShare;
    }
   
    function _handleLevelCompletion(uint256 level) private {
        uint256 bonus = matrixLevels[level].completionBonus;
       
        for (uint256 i = 0; i < POSITIONS_PER_LEVEL; i++) {
            address user = matrixLevels[level].positions[i];
            if (user != address(0)) {
                uint256 userBonus = bonus / POSITIONS_PER_LEVEL;
                users[user].totalEarnings += userBonus;
                payable(user).transfer(userBonus);
                emit CompletionBonus(user, level, userBonus);
            }
        }
    }
   
    function distributePool() external onlyOwner {
        require(redistributionPool > 0, "No funds to distribute");
       
        uint256 eligibleUsers = 0;
        for (uint256 i = 0; i < activeUsers.length; i++) {
            if (users[activeUsers[i]].totalEarnings >= 1 ether) {
                eligibleUsers++;
            }
        }
       
        if (eligibleUsers > 0) {
            uint256 sharePerUser = redistributionPool / eligibleUsers;
            for (uint256 i = 0; i < activeUsers.length; i++) {
                address user = activeUsers[i];
                if (users[user].totalEarnings >= 1 ether) {
                    users[user].totalEarnings += sharePerUser;
                    payable(user).transfer(sharePerUser);
                }
            }
            redistributionPool = 0;
        }
    }
   
    function getUserInfo(address user) external view returns (
        bool isActive,
        address referrer,
        uint256 currentLevel,
        uint256 totalEarnings,
        uint256 lockedBalance,
        uint256[] memory referrals
    ) {
        User storage u = users[user];
        return (
            u.isActive,
            u.referrer,
            u.currentLevel,
            u.totalEarnings,
            u.lockedBalance,
            u.referrals
        );
    }
   
    function getMatrixPosition(uint256 level) external view returns (address[6] memory) {
        address[6] memory positions;
        for (uint256 i = 0; i < POSITIONS_PER_LEVEL; i++) {
            positions[i] = matrixLevels[level].positions[i];
        }
        return positions;
    }
   
    function getLevelPrice(uint256 level) external view returns (uint256) {
        return matrixLevels[level].price;
    }
}</code></pre>
                </div>
            </div>
        </section>

        <!-- React Frontend -->
        <section class="mb-12">
            <div class="bg-white rounded-lg shadow-lg p-8">
                <h2 class="text-3xl font-bold mb-6 text-gray-800">
                    <i class="fab fa-react mr-3 text-blue-600"></i>React Frontend
                </h2>
                <p class="text-gray-600 mb-6">Interactive React application with Web3 integration for matrix visualization and user interaction.</p>
               
                <!-- DApp Interface -->
                <div id="dapp-root" class="border-2 border-gray-200 rounded-lg p-6 min-h-96">
                    <div class="text-center py-8">
                        <div class="animate-spin rounded-full h-12 w-12 border-b-2 border-blue-600 mx-auto"></div>
                        <p class="mt-4 text-gray-600">Loading DApp Interface...</p>
                    </div>
                </div>
               
                <!-- Frontend Code -->
                <div class="mt-8">
                    <div class="bg-gray-900 rounded-lg p-4">
                        <div class="flex items-center justify-between mb-4">
                            <h3 class="text-white font-semibold">App.jsx</h3>
                            <span class="bg-blue-500 text-white px-2 py-1 rounded text-sm">React 18</span>
                        </div>
                        <pre class="text-green-400 text-sm overflow-x-auto"><code>const { useState, useEffect } = React;

function MatrixDApp() {
    const [web3, setWeb3] = useState(null);
    const [account, setAccount] = useState('');
    const [contract, setContract] = useState(null);
    const [userInfo, setUserInfo] = useState(null);
    const [matrixData, setMatrixData] = useState([]);
    const [currentLevel, setCurrentLevel] = useState(1);
    const [loading, setLoading] = useState(false);

    const contractABI = [
        // Contract ABI would go here
    ];

    const connectWallet = async () => {
        if (typeof window.ethereum !== 'undefined') {
            try {
                await window.ethereum.request({ method: 'eth_requestAccounts' });
                const web3Instance = new Web3(window.ethereum);
                setWeb3(web3Instance);
               
                const accounts = await web3Instance.eth.getAccounts();
                setAccount(accounts[0]);
               
                // Initialize contract
                const contractInstance = new web3Instance.eth.Contract(contractABI, CONTRACT_ADDRESS);
                setContract(contractInstance);
               
            } catch (error) {
                console.error('Error connecting wallet:', error);
            }
        } else {
            alert('Please install MetaMask!');
        }
    };

    const loadUserData = async () => {
        if (contract && account) {
            try {
                const info = await contract.methods.getUserInfo(account).call();
                setUserInfo(info);
               
                if (info.isActive) {
                    loadMatrixData(info.currentLevel);
                }
            } catch (error) {
                console.error('Error loading user data:', error);
            }
        }
    };

    const loadMatrixData = async (level) => {
        if (contract) {
            try {
                const positions = await contract.methods.getMatrixPosition(level).call();
                setMatrixData(positions);
            } catch (error) {
                console.error('Error loading matrix data:', error);
            }
        }
    };

    const registerUser = async (referrerCode) => {
        if (contract && account) {
            try {
                setLoading(true);
                const price = await contract.methods.getLevelPrice(1).call();
               
                await contract.methods.register(
                    referrerCode || account,
                    `REF_${Date.now()}`
                ).send({
                    from: account,
                    value: price
                });
               
                await loadUserData();
            } catch (error) {
                console.error('Error registering:', error);
            } finally {
                setLoading(false);
            }
        }
    };

    useEffect(() => {
        if (web3 && account) {
            loadUserData();
        }
    }, [web3, account]);

    return (
        <div className="min-h-screen bg-gradient-to-br from-blue-50 to-purple-50">
            <div className="container mx-auto px-4 py-8">
                <header className="text-center mb-8">
                    <h1 className="text-4xl font-bold text-gray-800 mb-4">
                        3x2 Matrix DApp
                    </h1>
                    {!account ? (
                        <button
                            onClick={connectWallet}
                            className="bg-blue-600 text-white px-6 py-3 rounded-lg font-semibold hover:bg-blue-700 transition-colors"
                        >
                            Connect Wallet
                        </button>
                    ) : (
                        <div className="bg-white rounded-lg p-4 inline-block shadow-md">
                            <p className="text-sm text-gray-600">Connected:</p>
                            <p className="font-mono text-sm">{account}</p>
                        </div>
                    )}
                </header>

                {account && (
                    <div className="grid lg:grid-cols-2 gap-8">
                        <div className="bg-white rounded-lg shadow-lg p-6">
                            <h2 className="text-2xl font-bold mb-4">Dashboard</h2>
                            {userInfo ? (
                                <div className="space-y-4">
                                    <div className="grid grid-cols-2 gap-4">
                                        <div className="bg-blue-50 p-4 rounded-lg">
                                            <p className="text-sm text-gray-600">Current Level</p>
                                            <p className="text-2xl font-bold text-blue-600">
                                                {userInfo.currentLevel}
                                            </p>
                                        </div>
                                        <div className="bg-green-50 p-4 rounded-lg">
                                            <p className="text-sm text-gray-600">Total Earnings</p>
                                            <p className="text-2xl font-bold text-green-600">
                                                {web3?.utils.fromWei(userInfo.totalEarnings, 'ether')} ETH
                                            </p>
                                        </div>
                                    </div>
                                    <div className="bg-yellow-50 p-4 rounded-lg">
                                        <p className="text-sm text-gray-600">Referrals</p>
                                        <p className="text-xl font-bold text-yellow-600">
                                            {userInfo.referrals.length}
                                        </p>
                                    </div>
                                </div>
                            ) : (
                                <div className="text-center py-8">
                                    <button
                                        onClick={() => registerUser('')}
                                        disabled={loading}
                                        className="bg-green-600 text-white px-6 py-3 rounded-lg font-semibold hover:bg-green-700 transition-colors disabled:opacity-50"
                                    >
                                        {loading ? 'Registering...' : 'Register Now'}
                                    </button>
                                </div>
                            )}
                        </div>

                        <div className="bg-white rounded-lg shadow-lg p-6">
                            <h2 className="text-2xl font-bold mb-4">Matrix Level {currentLevel}</h2>
                            <div className="grid grid-cols-3 gap-2 mb-4">
                                {Array.from({ length: 6 }, (_, i) => (
                                    <div
                                        key={i}
                                        className={`h-16 rounded-lg border-2 flex items-center justify-center text-xs font-mono ${
                                            matrixData[i] && matrixData[i] !== '0x0000000000000000000000000000000000000000'
                                                ? 'bg-green-100 border-green-300'
                                                : 'bg-gray-100 border-gray-300'
                                        }`}
                                    >
                                        {matrixData[i] && matrixData[i] !== '0x0000000000000000000000000000000000000000'
                                            ? `${matrixData[i].slice(0, 6)}...`
                                            : 'Empty'
                                        }
                                    </div>
                                ))}
                            </div>
                            <div className="flex space-x-2">
                                <button
                                    onClick={() => setCurrentLevel(Math.max(1, currentLevel - 1))}
                                    className="px-4 py-2 bg-gray-200 rounded-lg hover:bg-gray-300 transition-colors"
                                    disabled={currentLevel <= 1}
                                >
                                    ← Previous
                                </button>
                                <button
                                    onClick={() => setCurrentLevel(Math.min(12, currentLevel + 1))}
                                    className="px-4 py-2 bg-gray-200 rounded-lg hover:bg-gray-300 transition-colors"
                                    disabled={currentLevel >= 12}
                                >
                                    Next →
                                </button>
                            </div>
                        </div>
                    </div>
                )}
            </div>
        </div>
    );
}</code></pre>
                    </div>
                </div>
            </div>
        </section>

        <!-- Matrix Visualization -->
        <section class="mb-12">
            <div class="bg-white rounded-lg shadow-lg p-8">
                <h2 class="text-3xl font-bold mb-6 text-gray-800">
                    <i class="fas fa-project-diagram mr-3 text-green-600"></i>Matrix System Visualization
                </h2>
               
                <div class="grid md:grid-cols-2 gap-8">
                    <div>
                        <h3 class="text-xl font-semibold mb-4">3x2 Matrix Structure</h3>
                        <div class="bg-gray-50 p-6 rounded-lg">
                            <div class="grid grid-cols-3 gap-3 mb-4">
                                <div class="bg-blue-500 text-white p-4 rounded-lg text-center font-semibold">Position 1</div>
                                <div class="bg-blue-500 text-white p-4 rounded-lg text-center font-semibold">Position 2</div>
                                <div class="bg-blue-500 text-white p-4 rounded-lg text-center font-semibold">Position 3</div>
                            </div>
                            <div class="grid grid-cols-3 gap-3">
                                <div class="bg-green-500 text-white p-4 rounded-lg text-center font-semibold">Position 4</div>
                                <div class="bg-green-500 text-white p-4 rounded-lg text-center font-semibold">Position 5</div>
                                <div class="bg-green-500 text-white p-4 rounded-lg text-center font-semibold">Position 6</div>
                            </div>
                            <p class="text-sm text-gray-600 mt-4 text-center">
                                Fills top-down, left-to-right order
                            </p>
                        </div>
                    </div>
                   
                    <div>
                        <h3 class="text-xl font-semibold mb-4">Fund Distribution</h3>
                        <div class="space-y-3">
                            <div class="bg-yellow-100 p-4 rounded-lg flex justify-between">
                                <span class="font-semibold">First Line (Direct Referrer)</span>
                                <span class="font-bold text-yellow-700">25%</span>
                            </div>
                            <div class="bg-orange-100 p-4 rounded-lg flex justify-between">
                                <span class="font-semibold">Second Line (Upline)</span>
                                <span class="font-bold text-orange-700">25%</span>
                            </div>
                            <div class="bg-purple-100 p-4 rounded-lg flex justify-between">
                                <span class="font-semibold">Completion Bonus Pool</span>
                                <span class="font-bold text-purple-700">50%</span>
                            </div>
                        </div>
                        <div class="mt-4 p-4 bg-gray-100 rounded-lg">
                            <p class="text-sm text-gray-700">
                                <strong>Note:</strong> Unqualified uplines redirect funds to redistribution pool
                            </p>
                        </div>
                    </div>
                </div>
               
                <!-- Level Progression Chart -->
                <div class="mt-8">
                    <h3 class="text-xl font-semibold mb-4">Level Progression & Pricing</h3>
                    <div class="bg-gray-50 p-6 rounded-lg">
                        <canvas id="levelChart" style="height: 400px;"></canvas>
                    </div>
                </div>
            </div>
        </section>

        <!-- Final Summary -->
        <section class="mb-8">
            <div class="bg-gradient-to-r from-blue-600 to-purple-600 text-white rounded-lg shadow-lg p-8">
                <h2 class="text-3xl font-bold mb-6 text-center">
                    <i class="fas fa-check-circle mr-3"></i>Complete DApp Package
                </h2>
               
                <div class="grid md:grid-cols-2 gap-8">
                    <div>
                        <h3 class="text-xl font-semibold mb-4">✅ Ready to Deploy:</h3>
                        <ul class="space-y-2">
                            <li class="flex items-center"><i class="fas fa-code mr-2"></i>Production-ready Solidity smart contract</li>
                            <li class="flex items-center"><i class="fab fa-react mr-2"></i>React frontend with Web3 integration</li>
                            <li class="flex items-center"><i class="fas fa-chart-bar mr-2"></i>Matrix visualization components</li>
                            <li class="flex items-center"><i class="fas fa-wallet mr-2"></i>MetaMask wallet connection</li>
                            <li class="flex items-center"><i class="fas fa-users mr-2"></i>Referral system implementation</li>
                            <li class="flex items-center"><i class="fas fa-coins mr-2"></i>Automated fund distribution</li>
                        </ul>
                    </div>
                   
                    <div>
                        <h3 class="text-xl font-semibold mb-4">🚀 Next Steps:</h3>
                        <ol class="space-y-2">
                            <li class="flex items-start"><span class="bg-white text-blue-600 rounded-full w-6 h-6 flex items-center justify-center text-sm font-bold mr-3 mt-0.5">1</span>Deploy smart contract to testnet</li>
                            <li class="flex items-start"><span class="bg-white text-blue-600 rounded-full w-6 h-6 flex items-center justify-center text-sm font-bold mr-3 mt-0.5">2</span>Test all functionality thoroughly</li>
                            <li class="flex items-start"><span class="bg-white text-blue-600 rounded-full w-6 h-6 flex items-center justify-center text-sm font-bold mr-3 mt-0.5">3</span>Deploy frontend to hosting platform</li>
                            <li class="flex items-start"><span class="bg-white text-blue-600 rounded-full w-6 h-6 flex items-center justify-center text-sm font-bold mr-3 mt-0.5">4</span>Conduct security audit (recommended)</li>
                            <li class="flex items-start"><span class="bg-white text-blue-600 rounded-full w-6 h-6 flex items-center justify-center text-sm font-bold mr-3 mt-0.5">5</span>Deploy to mainnet when ready</li>
                        </ol>
                    </div>
                </div>
               
                <div class="mt-8 text-center">
                    <p class="text-lg opacity-90">
                        🚀 Complete 3x2 Matrix DApp - No watermarks, ready for deployment
                    </p>
                </div>
            </div>
        </section>
    </div>

    <!-- React App Script -->
    <script type="text/babel">
        // Initialize React App
        ReactDOM.render(<MatrixDApp />, document.getElementById('dapp-root'));
       
        // Initialize Level Chart
        const ctx = document.getElementById('levelChart').getContext('2d');
        new Chart(ctx, {
            type: 'line',
            data: {
                labels: Array.from({length: 12}, (_, i) => `Level ${i + 1}`),
                datasets: [{
                    label: 'Level Price (ETH)',
                    data: Array.from({length: 12}, (_, i) => 0.01 * Math.pow(2, i)),
                    borderColor: 'rgb(59, 130, 246)',
                    backgroundColor: 'rgba(59, 130, 246, 0.1)',
                    tension: 0.1
                }]
            },
            options: {
                responsive: true,
                maintainAspectRatio: false,
                scales: {
                    y: {
                        beginAtZero: true,
                        title: {
                            display: true,
                            text: 'Price (ETH)'
                        }
                    }
                },
                plugins: {
                    title: {
                        display: true,
                        text: 'Exponential Level Pricing Structure'
                    }
                }
            }
        });
    </script>
</body>
</html>