// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

contract TokenStorageV1 is Initializable {
    uint256 public constant INITIAL_SUPPLY = 100_000_000 * 10**18; // 100 million tokens
    uint256 public constant MAX_TOTAL_BURN = INITIAL_SUPPLY / 10; // 10% of initial supply
    uint256 public constant BURN_RATE_PRECISION = 100000; // Precision for burn rate calculations

    uint16 internal _burnRate;
    uint256 internal _totalBurned;
    bool internal _initialized;
    
    uint256[47] private __gap;
}

contract AutoBurnToken is 
    TokenStorageV1,
    ERC20Upgradeable, 
    ERC20PausableUpgradeable,
    OwnableUpgradeable, 
    UUPSUpgradeable 
{
    // Events
    event BurnRateUpdated(uint16 oldRate, uint16 newRate);
    event AutoBurnExecuted(address from, address to, uint256 burnAmount);
    event MaxBurnLimitReached();
    
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address initialOwner
    ) initializer public {
        require(!_initialized, "Contract already initialized");
        
        __ERC20_init("AutoBurnToken", "ABT");
        __ERC20Pausable_init();
        __Ownable_init(initialOwner);
        __UUPSUpgradeable_init();
        
        _burnRate = 1; // Set to 0.001%
        _totalBurned = 0;
        
        // Mint entire supply to initial owner
        _mint(initialOwner, INITIAL_SUPPLY);
        _initialized = true;
    }

    // View Functions
    function burnRate() public view virtual returns (uint16) {
        return _burnRate;
    }

    function totalBurned() public view virtual returns (uint256) {
        return _totalBurned;
    }

    function remainingBurnAllowance() public view virtual returns (uint256) {
        if (_totalBurned >= MAX_TOTAL_BURN) {
            return 0;
        }
        return MAX_TOTAL_BURN - _totalBurned;
    }

    // Admin Functions
    function setBurnRate(uint16 newRate) external virtual onlyOwner {
        uint16 oldRate = _burnRate;
        _burnRate = newRate;
        emit BurnRateUpdated(oldRate, newRate);
    }

    function pause() external virtual onlyOwner {
        _pause();
    }

    function unpause() external virtual onlyOwner {
        _unpause();
    }

    // Internal Functions
    function _authorizeUpgrade(address newImplementation) internal virtual override onlyOwner {}

    function _update(
        address from,
        address to,
        uint256 amount
    ) internal virtual override(ERC20Upgradeable, ERC20PausableUpgradeable) {
        // Prevent new minting after initialization
        if (from == address(0) && _initialized) {
            revert("Minting is not allowed after initialization");
        }

        if (from != address(0) && to != address(0)) {
            // Only proceed with burn if we haven't reached the maximum
            if (_totalBurned < MAX_TOTAL_BURN) {
                // Calculate potential burn amount (0.001% = multiply by 1 then divide by BURN_RATE_PRECISION)
                uint256 burnAmount = (amount * _burnRate) / BURN_RATE_PRECISION;
                
                // Adjust burn amount if it would exceed max total burn
                if (_totalBurned + burnAmount > MAX_TOTAL_BURN) {
                    burnAmount = MAX_TOTAL_BURN - _totalBurned;
                }
                
                if (burnAmount > 0) {
                    // Reduce the transfer amount by burn amount
                    uint256 transferAmount = amount - burnAmount;
                    
                    // Update total burned before transfers
                    _totalBurned += burnAmount;
                    
                    // First do the burn transfer
                    super._update(from, address(0), burnAmount);
                    
                    // Then do the main transfer with reduced amount
                    super._update(from, to, transferAmount);
                    
                    // Emit auto burn event
                    emit AutoBurnExecuted(from, to, burnAmount);
                    
                    // Emit event if we've reached the max burn limit
                    if (_totalBurned >= MAX_TOTAL_BURN) {
                        emit MaxBurnLimitReached();
                    }
                    
                    // Skip the default update since we handled it
                    return;
                }
            }
        }
        
        // For all other cases (no burn needed), use the default implementation
        super._update(from, to, amount);
    }

    /**
     * @dev This empty reserved space is put in place to allow future versions to add new
     * variables without shifting down storage in the inheritance chain.
     */
    uint256[47] private __gap;
}
