// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/token/ERC1155/ERC1155Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

interface IFtso {
    function getCurrentPriceWithDecimals() external view returns (uint256 _price, uint256 _timestamp, uint256 _decimals);
}

contract MembershipNFT is Initializable, ERC1155Upgradeable, OwnableUpgradeable, UUPSUpgradeable {
    
    // Name and symbol for the token
    string public name;
    string public symbol;
    
    // FTSO Price Feed
    IFtso public ftso;
    
    // Tier Constants with Updated Names
    uint256 public constant TOP_TIER = 0;
    uint256 public constant RHODIUM = 1;
    uint256 public constant PLATINUM = 2;
    uint256 public constant GOLD = 3;
    uint256 public constant RUTHENIUM = 4;
    uint256 public constant IRIDIUM = 5;
    uint256 public constant OSMIUM = 6;
    uint256 public constant PALLADIUM = 7;
    uint256 public constant RHENIUM = 8;
    uint256 public constant SILVER = 9;

    // Struct for tier ownership information
    struct TierOwnership {
        uint256 tier;
        uint256 amount;
        uint256 mintTimestamp;
    }

    // USD prices (with 2 decimals, e.g., 960000 = $9,600.00)
    mapping(uint256 => uint256) public tierUSDPrices;
    
    // Other state variables
    address public poolWallet;
    address public companyWallet;
    address public partnerWallet;
    mapping(uint256 => string) public tierURIs;
    mapping(uint256 => uint256) public maxSupplyPerTier;
    mapping(uint256 => uint256) public currentSupplyPerTier;
    mapping(address => address) public referrer;
    uint256 public totalMaxSupply;
    mapping(address => mapping(uint256 => uint256)) public userMintTimestamps;

    // Enhanced referral tracking
    struct ReferralInfo {
        uint256 totalReferrals;       // Total number of successful referrals
        uint256 totalEarned;          // Total amount earned from referrals in FLR
        uint256 lastReferralTime;     // Timestamp of last successful referral
        uint256[] referralAmounts;    // Array of individual referral amounts
        uint256[] referralTimes;      // Array of referral timestamps
        address[] referredUsers;      // Array of referred user addresses
        uint256[] referralTiers;      // Array of tiers that were referred
    }

    // Mapping to store referral information
    mapping(address => ReferralInfo) public referralStats;
    
    // Events
    event MembershipMinted(
        address indexed account, 
        uint256 indexed tier, 
        uint256 amount, 
        uint256 timestamp,
        address referrer,
        uint256 usdPrice,
        uint256 flrAmount
    );
    event TierUSDPriceUpdated(uint256 indexed tier, uint256 newUSDPrice);
    event TierURIUpdated(uint256 indexed tier, string newURI);
    event WalletUpdated(string indexed walletType, address newWallet);
    event FTSOUpdated(address newFtso);
    event ReferralPayment(
        address indexed referrer,
        address indexed buyer,
        uint256 indexed tier,
        uint256 referralAmount,
        uint256 referralPercentage
    );
    event ReferralRewardsClaimed(
        address indexed referrer,
        uint256 totalAmount,
        uint256 timestamp
    );

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        string memory _baseUri, 
        address _poolWallet, 
        address _companyWallet,
        address _partnerWallet,
        address _ftso
    ) public initializer {
        __ERC1155_init(_baseUri);
        __Ownable_init(msg.sender);
        __UUPSUpgradeable_init();

        name = "Defi Bull Membership NFTs";
        symbol = "BDWM";
        
        // Set wallets and FTSO
        poolWallet = _poolWallet;
        companyWallet = _companyWallet;
        partnerWallet = _partnerWallet;
        ftso = IFtso(_ftso);
        
        // Initialize tier USD prices (in cents)
        tierUSDPrices[TOP_TIER] = 900;      // $9.00
        tierUSDPrices[RHODIUM] = 450;       // $4.50
        tierUSDPrices[PLATINUM] = 225;      // $2.25
        tierUSDPrices[GOLD] = 110;          // $1.10
        tierUSDPrices[RUTHENIUM] = 50;      // $0.50
        tierUSDPrices[IRIDIUM] = 25;        // $0.25
        tierUSDPrices[OSMIUM] = 12;         // $0.12
        tierUSDPrices[PALLADIUM] = 6;       // $0.06
        tierUSDPrices[RHENIUM] = 3;         // $0.03
        tierUSDPrices[SILVER] = 1;          // $0.01
        
        // Initialize max supply per tier
        maxSupplyPerTier[TOP_TIER] = 25;
        maxSupplyPerTier[RHODIUM] = 50;
        maxSupplyPerTier[PLATINUM] = 100;
        maxSupplyPerTier[GOLD] = 200;
        maxSupplyPerTier[RUTHENIUM] = 400;
        maxSupplyPerTier[IRIDIUM] = 800;
        maxSupplyPerTier[OSMIUM] = 1600;
        maxSupplyPerTier[PALLADIUM] = 3200;
        maxSupplyPerTier[RHENIUM] = 6400;
        maxSupplyPerTier[SILVER] = 12800;

        totalMaxSupply = 25275; // Total including SILVER tier
    }

    // Price calculation functions
    function getFlareAmount(uint256 usdPrice) public view returns (uint256) {
        // Get current price from FTSO
        // Price comes with 5 decimals (e.g., 12345 = $0.12345)
        (uint256 flarePrice, , ) = ftso.getCurrentPriceWithDecimals();
        
        // usdPrice comes in cents (2 decimals, e.g., 10000 = $100.00)
        // Convert USD cents to full USD and calculate FLR amount
        uint256 flareAmount = (usdPrice * 1e18 * 1e5) / (flarePrice * 100);
        return flareAmount;
    }

    // Test functions for price verification
    function getCurrentFlarePriceRaw() external view returns (
        uint256 price, 
        uint256 timestamp, 
        uint256 decimals
    ) {
        return ftso.getCurrentPriceWithDecimals();
    }

    function testPriceConversion(uint256 usdCents) external view returns (
        uint256 flarePriceRaw,
        uint256 flareAmount,
        string memory explanation
    ) {
        (uint256 currentPrice, , ) = ftso.getCurrentPriceWithDecimals();
        uint256 requiredFlare = getFlareAmount(usdCents);
        
        return (
            currentPrice,
            requiredFlare,
            "FlarePriceRaw shows FTSO price with 5 decimals, flareAmount shows required FLR in wei"
        );
    }

    function mint(uint256 tier, uint256 amount, address _referrer) external payable {
        require(tier <= SILVER, "Invalid tier");
        require(amount > 0, "Amount must be greater than 0");
        require(
            currentSupplyPerTier[tier] + amount <= maxSupplyPerTier[tier],
            "Exceeds max supply for tier"
        );
        
        uint256 usdPrice = tierUSDPrices[tier] * amount;
        uint256 flareRequired = getFlareAmount(usdPrice);
        require(msg.value == flareRequired, "Incorrect payment amount");
        
        // Calculate shares
        uint256 partnerShare = (msg.value * 2) / 100;  // 2%
        uint256 remainingAmount = msg.value - partnerShare;
        uint256 poolShare = remainingAmount / 2;    // 49% of total
        uint256 companyShare = remainingAmount / 2; // 49% of total
        
        // Handle referral based on tier
        if (_referrer != address(0) && _referrer != msg.sender) {
            uint256 referralAmount;
            uint256 referralPercentage;
            
            if (tier <= RUTHENIUM) {
                referralAmount = (companyShare * 5) / 100;
                referralPercentage = 5;
            } else {
                referralAmount = (companyShare * 10) / 100;
                referralPercentage = 10;
            }
            
            (bool referralSuccess,) = payable(_referrer).call{value: referralAmount}("");
            require(referralSuccess, "Referral payment failed");
            companyShare -= referralAmount;
            
            // Update referral tracking with detailed information
            ReferralInfo storage refInfo = referralStats[_referrer];
            if (referrer[msg.sender] == address(0)) {
                referrer[msg.sender] = _referrer;
                refInfo.totalReferrals += 1;
            }
            refInfo.totalEarned += referralAmount;
            refInfo.lastReferralTime = block.timestamp;
            refInfo.referralAmounts.push(referralAmount);
            refInfo.referralTimes.push(block.timestamp);
            refInfo.referredUsers.push(msg.sender);
            refInfo.referralTiers.push(tier);
            
            emit ReferralPayment(_referrer, msg.sender, tier, referralAmount, referralPercentage);
            emit ReferralRewardsClaimed(_referrer, referralAmount, block.timestamp);
        }
        
        // Transfer shares
        (bool partnerSuccess,) = payable(partnerWallet).call{value: partnerShare}("");
        require(partnerSuccess, "Partner payment failed");
        
        (bool poolSuccess,) = payable(poolWallet).call{value: poolShare}("");
        require(poolSuccess, "Pool payment failed");
        
        (bool companySuccess,) = payable(companyWallet).call{value: companyShare}("");
        require(companySuccess, "Company payment failed");
        
        // Record mint timestamp and mint NFT
        uint256 timestamp = block.timestamp;
        userMintTimestamps[msg.sender][tier] = timestamp;
        _mint(msg.sender, tier, amount, "");
        currentSupplyPerTier[tier] += amount;
        
        emit MembershipMinted(msg.sender, tier, amount, timestamp, _referrer, usdPrice, msg.value);
    }

    // Admin functions
    function setFTSO(address _newFtso) external onlyOwner {
        ftso = IFtso(_newFtso);
        emit FTSOUpdated(_newFtso);
    }

    function setTierUSDPrice(uint256 tier, uint256 newUSDPrice) external onlyOwner {
        require(tier <= SILVER, "Invalid tier");
        tierUSDPrices[tier] = newUSDPrice;
        emit TierUSDPriceUpdated(tier, newUSDPrice);
    }

    function setPoolWallet(address _newPoolWallet) external onlyOwner {
        poolWallet = _newPoolWallet;
        emit WalletUpdated("pool", _newPoolWallet);
    }

    function setCompanyWallet(address _newCompanyWallet) external onlyOwner {
        companyWallet = _newCompanyWallet;
        emit WalletUpdated("company", _newCompanyWallet);
    }

    function setPartnerWallet(address _newPartnerWallet) external onlyOwner {
        partnerWallet = _newPartnerWallet;
        emit WalletUpdated("partner", _newPartnerWallet);
    }

    function setTierURI(uint256 tier, string memory newUri) external onlyOwner {
        require(tier <= SILVER, "Invalid tier");
        tierURIs[tier] = newUri;
        emit TierURIUpdated(tier, newUri);
    }

    // View functions
    function uri(uint256 tier) public view override returns (string memory) {
        return tierURIs[tier];
    }
    
    function getTierUSDPrice(uint256 tier) external view returns (uint256) {
        return tierUSDPrices[tier];
    }
    
    function getTierFlarePrice(uint256 tier) external view returns (uint256) {
        return getFlareAmount(tierUSDPrices[tier]);
    }
    
    function getTierSupply(uint256 tier) external view returns (uint256 current, uint256 max) {
        return (currentSupplyPerTier[tier], maxSupplyPerTier[tier]);
    }

    function totalSupply() public view returns (uint256) {
        uint256 total = 0;
        for(uint256 i = 0; i <= SILVER; i++) {
            total += currentSupplyPerTier[i];
        }
        return total;
    }

    function maxSupply() public view returns (uint256) {
        return totalMaxSupply;
    }

    function getUserMintTimestamp(address user, uint256 tier) external view returns (uint256) {
        return userMintTimestamps[user][tier];
    }

    function getReferrer(address user) external view returns (address) {
        return referrer[user];
    }

    // Enhanced referral tracking view functions
    function getReferralHistory(address user) external view returns (
        address[] memory users,
        uint256[] memory amounts,
        uint256[] memory timestamps,
        uint256[] memory tiers
    ) {
        ReferralInfo storage info = referralStats[user];
        return (
            info.referredUsers,
            info.referralAmounts,
            info.referralTimes,
            info.referralTiers
        );
    }

    function getReferralStats(address user) external view returns (
        uint256 totalReferrals,
        uint256 totalEarned,
        uint256 lastReferralTime
    ) {
        ReferralInfo storage info = referralStats[user];
        return (
            info.totalReferrals,
            info.totalEarned,
            info.lastReferralTime
        );
    }

    function getTotalReferralRewards(address user) external view returns (uint256) {
        return referralStats[user].totalEarned;
    }

    // NFT ownership tracking functions
    function getUserTiers(address user) external view returns (TierOwnership[] memory) {
        // Create an array to hold owned tiers
        TierOwnership[] memory ownedTiers = new TierOwnership[](SILVER + 1);
        uint256 count = 0;
        
        // Check each tier
        for(uint256 i = 0; i <= SILVER; i++) {
            uint256 balance = balanceOf(user, i);
            if(balance > 0) {
                ownedTiers[count] = TierOwnership({
                    tier: i,
                    amount: balance,
                    mintTimestamp: userMintTimestamps[user][i]
                });
                count++;
            }
        }
        
        // Create properly sized array with only owned tiers
        TierOwnership[] memory result = new TierOwnership[](count);
        for(uint256 i = 0; i < count; i++) {
            result[i] = ownedTiers[i];
        }
        
        return result;
    }

    function getHighestTier(address user) external view returns (uint256) {
        for(uint256 i = 0; i <= SILVER; i++) {
            if(balanceOf(user, i) > 0) {
                return i;
            }
        }
        return type(uint256).max; // Return max uint if no tiers owned
    }

    function getTierBalance(address user, uint256 tier) external view returns (uint256) {
        require(tier <= SILVER, "Invalid tier");
        return balanceOf(user, tier);
    }

    function hasTier(address user, uint256 tier) external view returns (bool) {
        require(tier <= SILVER, "Invalid tier");
        return balanceOf(user, tier) > 0;
    }

    // Function to get all ownership info in a single call
    function getUserOwnershipInfo(address user) external view returns (
        TierOwnership[] memory ownedTiers,
        uint256 highestTier,
        uint256 totalNFTs
    ) {
        // Get owned tiers
        ownedTiers = this.getUserTiers(user);
        
        // Calculate highest tier and total NFTs
        highestTier = type(uint256).max;
        totalNFTs = 0;
        
        for(uint256 i = 0; i <= SILVER; i++) {
            uint256 balance = balanceOf(user, i);
            if(balance > 0) {
                if(highestTier == type(uint256).max || i < highestTier) {
                    highestTier = i;
                }
                totalNFTs += balance;
            }
        }
        
        return (ownedTiers, highestTier, totalNFTs);
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}
    
    // Add a storage gap for future upgrades
    uint256[50] private __gap;
}