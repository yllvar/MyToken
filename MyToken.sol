// SPDX-License-Identifier: Unlicensed
pragma solidity ^0.8.4;

import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@openzeppelin/contracts/utils/math/SafeMath.sol';
import '@openzeppelin/contracts/access/Ownable.sol';
import '@openzeppelin/contracts/utils/Address.sol';
import '@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol';
import '@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol';
import '@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol';

contract MyToken is Context, IERC20, Ownable {
    using SafeMath for uint256;
    using Address for address;

    // Marketing Address
    address payable public marketingAddress = payable(0xC62d840052eC09784775769b9ABB0373f8365800);
    // Dead Address for burning tokens
    address public immutable deadAddress = 0x000000000000000000000000000000000000dEaD;

    // Mapping to store reflection balances
    mapping(address => uint256) private _rOwned;
    // Mapping to store token balances
    mapping(address => uint256) private _tOwned;
    // Mapping to store allowances
    mapping(address => mapping(address => uint256)) private _allowances;
    // Mapping to store sniper status
    mapping(address => bool) private _isSniper;
    // Array to store confirmed snipers
    address[] private _confirmedSnipers;
    // Mapping to store fee exclusion status
    mapping(address => bool) private _isExcludedFromFee;
    // Mapping to store reward exclusion status
    mapping(address => bool) private _isExcluded;
    // Array to store excluded addresses
    address[] private _excluded;

    // Maximum value for uint256
    uint256 private constant MAX = ~uint256(0);
    // Total token supply
    uint256 private _tTotal = 128000000 * 10**9;
    // Total reflection supply
    uint256 private _rTotal = (MAX - (MAX % _tTotal));
    // Total fees collected
    uint256 private _tFeeTotal;

    // Token name and symbol
    string private _name = 'MyToken';
    string private _symbol = 'MYTKN';
    // Decimal places
    uint8 private _decimals = 9;

    // Tax fee percentage
    uint256 public _taxFee = 4;
    // Previous tax fee percentage (for temporary removal)
    uint256 private _previousTaxFee = _taxFee;
    // Liquidity fee percentage
    uint256 public _liquidityFee = 4;
    // Previous liquidity fee percentage (for temporary removal)
    uint256 private _previousLiquidityFee = _liquidityFee;
    // Fee rate for liquidity provision
    uint256 public _feeRate = 4;
    // Launch time of the contract
    uint256 launchTime;

    // Uniswap V2 Router
    IUniswapV2Router02 public uniswapV2Router;
    // Uniswap V2 Pair
    address public uniswapV2Pair;

    // Lock flag for swap and liquify process
    bool inSwapAndLiquify;
    // Trading status
    bool tradingOpen = false;

    // Events for swap operations
    event SwapETHForTokens(uint256 amountIn, address[] path);
    event SwapTokensForETH(uint256 amountIn, address[] path);

    // Modifier to lock the swap and liquify process
    modifier lockTheSwap {
        inSwapAndLiquify = true;
        _;
        inSwapAndLiquify = false;
    }

    // Constructor to initialize the contract
    constructor() {
        _rOwned[_msgSender()] = _rTotal;
        emit Transfer(address(0), _msgSender(), _tTotal);
    }

    // Function to initialize the contract with Uniswap settings
    function initContract() external onlyOwner {
        IUniswapV2Router02 _uniswapV2Router = IUniswapV2Router02(
            0x10ED43C718714eb63d5aA57B78B54704E256024E // PancakeSwap Router
        );
        uniswapV2Pair = IUniswapV2Factory(_uniswapV2Router.factory()).createPair(
            address(this),
            _uniswapV2Router.WETH()
        );
        uniswapV2Router = _uniswapV2Router;
        _isExcludedFromFee[owner()] = true;
        _isExcludedFromFee[address(this)] = true;
    }

    // Function to open trading and record launch time
    function openTrading() external onlyOwner {
        _liquidityFee = _previousLiquidityFee;
        _taxFee = _previousTaxFee;
        tradingOpen = true;
        launchTime = block.timestamp;
    }

    // Function to toggle trading status
    function toggleTrading() external onlyOwner {
        tradingOpen = tradingOpen ? false : true;
    }

    // Function to get the token name
    function name() public view returns (string memory) {
        return _name;
    }

    // Function to get the token symbol
    function symbol() public view returns (string memory) {
        return _symbol;
    }

    // Function to get the number of decimal places
    function decimals() public view returns (uint8) {
        return _decimals;
    }

    // Function to get the total token supply
    function totalSupply() public view override returns (uint256) {
        return _tTotal;
    }

    // Function to get the balance of a specific account
    function balanceOf(address account) public view override returns (uint256) {
        if (_isExcluded[account]) return _tOwned[account];
        return tokenFromReflection(_rOwned[account]);
    }

    // Function to transfer tokens to a recipient
    function transfer(address recipient, uint256 amount) public override returns (bool) {
        _transfer(_msgSender(), recipient, amount);
        return true;
    }

    // Function to get the allowance of a spender by an owner
    function allowance(address owner, address spender) public view override returns (uint256) {
        return _allowances[owner][spender];
    }

    // Function to approve a spender to spend tokens on behalf of the owner
    function approve(address spender, uint256 amount) public override returns (bool) {
        _approve(_msgSender(), spender, amount);
        return true;
    }

    // Function to transfer tokens from one address to another using allowance
    function transferFrom(address sender, address recipient, uint256 amount) public override returns (bool) {
        _transfer(sender, recipient, amount);
        _approve(
            sender,
            _msgSender(),
            _allowances[sender][_msgSender()].sub(
                amount,
                'ERC20: transfer amount exceeds allowance'
            )
        );
        return true;
    }

    // Function to increase the allowance of a spender
    function increaseAllowance(address spender, uint256 addedValue) public virtual returns (bool) {
        _approve(
            _msgSender(),
            spender,
            _allowances[_msgSender()][spender].add(addedValue)
        );
        return true;
    }

    // Function to decrease the allowance of a spender
    function decreaseAllowance(address spender, uint256 subtractedValue) public virtual returns (bool) {
        _approve(
            _msgSender(),
            spender,
            _allowances[_msgSender()][spender].sub(
                subtractedValue,
                'ERC20: decreased allowance below zero'
            )
        );
        return true;
    }

    // Function to check if an address is excluded from rewards
    function isExcludedFromReward(address account) external view returns (bool) {
        return _isExcluded[account];
    }

    // Function to get the total fees collected
    function totalFees() external view returns (uint256) {
        return _tFeeTotal;
    }

    // Function to deliver tokens to a recipient without fees
    function deliver(uint256 tAmount) external {
        address sender = _msgSender();
        require(
            !_isExcluded[sender],
            'Excluded addresses cannot call this function'
        );
        (uint256 rAmount, , , , , ) = _getValues(tAmount);
        _rOwned[sender] = _rOwned[sender].sub(rAmount);
        _rTotal = _rTotal.sub(rAmount);
        _tFeeTotal = _tFeeTotal.add(tAmount);
    }

    // Function to convert token amount to reflection amount
    function reflectionFromToken(uint256 tAmount, bool deductTransferFee) external view returns (uint256) {
        require(tAmount <= _tTotal, 'Amount must be less than supply');
        if (!deductTransferFee) {
            (uint256 rAmount, , , , , ) = _getValues(tAmount);
            return rAmount;
        } else {
            (, uint256 rTransferAmount, , , , ) = _getValues(tAmount);
            return rTransferAmount;
        }
    }

    // Function to convert reflection amount to token amount
    function tokenFromReflection(uint256 rAmount) public view returns (uint256) {
        require(rAmount <= _rTotal, 'Amount must be less than total reflections');
        uint256 currentRate = _getRate();
        return rAmount.div(currentRate);
    }

    // Function to exclude an address from rewards
    function excludeFromReward(address account) public onlyOwner {
        require(!_isExcluded[account], 'Account is already excluded');
        if (_rOwned[account] > 0) {
            _tOwned[account] = tokenFromReflection(_rOwned[account]);
        }
        _isExcluded[account] = true;
        _excluded.push(account);
    }

    // Function to include an address in rewards
    function includeInReward(address account) external onlyOwner {
        require(_isExcluded[account], 'Account is already included');
        for (uint256 i = 0; i < _excluded.length; i++) {
            if (_excluded[i] == account) {
                _excluded[i] = _excluded[_excluded.length - 1];
                _tOwned[account] = 0;
                _isExcluded[account] = false;
                _excluded.pop();
                break;
            }
        }
    }

    // Function to approve an allowance
    function _approve(address owner, address spender, uint256 amount) private {
        require(owner != address(0), 'ERC20: approve from the zero address');
        require(spender != address(0), 'ERC20: approve to the zero address');
        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

    // Function to handle token transfers
    function _transfer(address from, address to, uint256 amount) private {
        require(from != address(0), 'ERC20: transfer from the zero address');
        require(to != address(0), 'ERC20: transfer to the zero address');
        require(amount > 0, 'Transfer amount must be greater than zero');
        require(!_isSniper[to], 'You have no power here!');
        require(!_isSniper[msg.sender], 'You have no power here!');

        // Buy: Check if the transaction is a buy and trading is not open
        if (from == uniswapV2Pair && to != address(uniswapV2Router) && !_isExcludedFromFee[to]) {
            require(tradingOpen, 'Trading not yet enabled.');
            // Anti-sniper: Blacklist accounts that trade at the exact launch time
            if (block.timestamp == launchTime) {
                _isSniper[to] = true;
                _confirmedSnipers.push(to);
            }
        }

        uint256 contractTokenBalance = balanceOf(address(this));

        // Sell: Swap tokens to ETH and add liquidity if conditions are met
        if (!inSwapAndLiquify && tradingOpen && to == uniswapV2Pair) {
            if (contractTokenBalance > 0) {
                if (contractTokenBalance > balanceOf(uniswapV2Pair).mul(_feeRate).div(100)) {
                    contractTokenBalance = balanceOf(uniswapV2Pair).mul(_feeRate).div(100);
                }
                swapTokens(contractTokenBalance);
            }
        }

        bool takeFee = false;

        // Take fee only on swaps
        if ((from == uniswapV2Pair || to == uniswapV2Pair) && !(_isExcludedFromFee[from] || _isExcludedFromFee[to])) {
            takeFee = true;
        }

        _tokenTransfer(from, to, amount, takeFee);
    }

    // Function to swap tokens to ETH and send to marketing address
    function swapTokens(uint256 contractTokenBalance) private lockTheSwap {
        swapTokensForEth(contractTokenBalance);
        uint256 contractETHBalance = address(this).balance;
        if (contractETHBalance > 0) {
            sendETHToMarketing(address(this).balance);
        }
    }

    // Function to send ETH to the marketing address
    function sendETHToMarketing(uint256 amount) private {
        marketingAddress.call{value: amount}('');
    }

    // Function to swap tokens for ETH
    function swapTokensForEth(uint256 tokenAmount) private {
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = uniswapV2Router.WETH();

        _approve(address(this), address(uniswapV2Router), tokenAmount);

        uniswapV2Router.swapExactTokensForETHSupportingFeeOnTransferTokens(
            tokenAmount,
            0, // Accept any amount of ETH
            path,
            address(this),
            block.timestamp
        );

        emit SwapTokensForETH(tokenAmount, path);
    }

    // Function to add liquidity to the Uniswap pool
    function addLiquidity(uint256 tokenAmount, uint256 ethAmount) private {
        _approve(address(this), address(uniswapV2Router), tokenAmount);

        uniswapV2Router.addLiquidityETH{value: ethAmount}(
            address(this),
            tokenAmount,
            0, // Slippage is unavoidable
            0, // Slippage is unavoidable
            owner(),
            block.timestamp
        );
    }

    // Function to handle token transfers with fee logic
    function _tokenTransfer(address sender, address recipient, uint256 amount, bool takeFee) private {
        if (!takeFee) removeAllFee();
        if (_isExcluded[sender] && !_isExcluded[recipient]) {
            _transferFromExcluded(sender, recipient, amount);
        } else if (!_isExcluded[sender] && _isExcluded[recipient]) {
            _transferToExcluded(sender, recipient, amount);
        } else if (_isExcluded[sender] && _isExcluded[recipient]) {
            _transferBothExcluded(sender, recipient, amount);
        } else {
            _transferStandard(sender, recipient, amount);
        }
        if (!takeFee) restoreAllFee();
    }

    // Function to handle standard token transfers
    function _transferStandard(address sender, address recipient, uint256 tAmount) private {
        (uint256 rAmount, uint256 rTransferAmount, uint256 rFee, uint256 tTransferAmount, uint256 tFee, uint256 tLiquidity) = _getValues(tAmount);
        _rOwned[sender] = _rOwned[sender].sub(rAmount);
        _rOwned[recipient] = _rOwned[recipient].add(rTransferAmount);
        _takeLiquidity(tLiquidity);
        _reflectFee(rFee, tFee);
        emit Transfer(sender, recipient, tTransferAmount);
    }

    // Function to handle transfers from excluded addresses
    function _transferToExcluded(address sender, address recipient, uint256 tAmount) private {
        (uint256 rAmount, uint256 rTransferAmount, uint256 rFee, uint256 tTransferAmount, uint256 tFee, uint256 tLiquidity) = _getValues(tAmount);
        _rOwned[sender] = _rOwned[sender].sub(rAmount);
        _tOwned[recipient] = _tOwned[recipient].add(tTransferAmount);
        _rOwned[recipient] = _rOwned[recipient].add(rTransferAmount);
        _takeLiquidity(tLiquidity);
        _reflectFee(rFee, tFee);
        emit Transfer(sender, recipient, tTransferAmount);
    }

    // Function to handle transfers to excluded addresses
    function _transferFromExcluded(address sender, address recipient, uint256 tAmount) private {
        (uint256 rAmount, uint256 rTransferAmount, uint256 rFee, uint256 tTransferAmount, uint256 tFee, uint256 tLiquidity) = _getValues(tAmount);
        _tOwned[sender] = _tOwned[sender].sub(tAmount);
        _rOwned[sender] = _rOwned[sender].sub(rAmount);
        _rOwned[recipient] = _rOwned[recipient].add(rTransferAmount);
        _takeLiquidity(tLiquidity);
        _reflectFee(rFee, tFee);
        emit Transfer(sender, recipient, tTransferAmount);
    }

    // Function to handle transfers between excluded addresses
    function _transferBothExcluded(address sender, address recipient, uint256 tAmount) private {
        (uint256 rAmount, uint256 rTransferAmount, uint256 rFee, uint256 tTransferAmount, uint256 tFee, uint256 tLiquidity) = _getValues(tAmount);
        _tOwned[sender] = _tOwned[sender].sub(tAmount);
        _rOwned[sender] = _rOwned[sender].sub(rAmount);
        _tOwned[recipient] = _tOwned[recipient].add(tTransferAmount);
        _rOwned[recipient] = _rOwned[recipient].add(rTransferAmount);
        _takeLiquidity(tLiquidity);
        _reflectFee(rFee, tFee);
        emit Transfer(sender, recipient, tTransferAmount);
    }

    // Function to reflect fees
    function _reflectFee(uint256 rFee, uint256 tFee) private {
        _rTotal = _rTotal.sub(rFee);
        _tFeeTotal = _tFeeTotal.add(tFee);
    }

    // Function to get values for token and reflection amounts
    function _getValues(uint256 tAmount) private view returns (uint256, uint256, uint256, uint256, uint256, uint256) {
        (uint256 tTransferAmount, uint256 tFee, uint256 tLiquidity) = _getTValues(tAmount);
        (uint256 rAmount, uint256 rTransferAmount, uint256 rFee) = _getRValues(tAmount, tFee, tLiquidity, _getRate());
        return (rAmount, rTransferAmount, rFee, tTransferAmount, tFee, tLiquidity);
    }

    // Function to get token values (transfer amount, fee, liquidity)
    function _getTValues(uint256 tAmount) private view returns (uint256, uint256, uint256) {
        uint256 tFee = calculateTaxFee(tAmount);
        uint256 tLiquidity = calculateLiquidityFee(tAmount);
        uint256 tTransferAmount = tAmount.sub(tFee).sub(tLiquidity);
        return (tTransferAmount, tFee, tLiquidity);
    }

    // Function to get reflection values (reflection amount, transfer amount, fee)
    function _getRValues(uint256 tAmount, uint256 tFee, uint256 tLiquidity, uint256 currentRate) private pure returns (uint256, uint256, uint256) {
        uint256 rAmount = tAmount.mul(currentRate);
        uint256 rFee = tFee.mul(currentRate);
        uint256 rLiquidity = tLiquidity.mul(currentRate);
        uint256 rTransferAmount = rAmount.sub(rFee).sub(rLiquidity);
        return (rAmount, rTransferAmount, rFee);
    }

    // Function to get the current rate
    function _getRate() private view returns (uint256) {
        (uint256 rSupply, uint256 tSupply) = _getCurrentSupply();
        return rSupply.div(tSupply);
    }

    // Function to get the current supply of tokens and reflections
    function _getCurrentSupply() private view returns (uint256, uint256) {
        uint256 rSupply = _rTotal;
        uint256 tSupply = _tTotal;
        for (uint256 i = 0; i < _excluded.length; i++) {
            if (_rOwned[_excluded[i]] > rSupply || _tOwned[_excluded[i]] > tSupply) return (_rTotal, _tTotal);
            rSupply = rSupply.sub(_rOwned[_excluded[i]]);
            tSupply = tSupply.sub(_tOwned[_excluded[i]]);
        }
        if (rSupply < _rTotal.div(_tTotal)) return (_rTotal, _tTotal);
        return (rSupply, tSupply);
    }

    // Function to take liquidity tokens
    function _takeLiquidity(uint256 tLiquidity) private {
        uint256 currentRate = _getRate();
        uint256 rLiquidity = tLiquidity.mul(currentRate);
        _rOwned[address(this)] = _rOwned[address(this)].add(rLiquidity);
        if (_isExcluded[address(this)]) _tOwned[address(this)] = _tOwned[address(this)].add(tLiquidity);
    }

    // Function to calculate tax fee
    function calculateTaxFee(uint256 _amount) private view returns (uint256) {
        return _amount.mul(_taxFee).div(10**2);
    }

    // Function to calculate liquidity fee
    function calculateLiquidityFee(uint256 _amount) private view returns (uint256) {
        return _amount.mul(_liquidityFee).div(10**2);
    }

    // Function to remove all fees temporarily
    function removeAllFee() private {
        if (_taxFee == 0 && _liquidityFee == 0) return;
        _previousTaxFee = _taxFee;
        _previousLiquidityFee = _liquidityFee;
        _taxFee = 0;
        _liquidityFee = 0;
    }

    // Function to restore previous fees
    function restoreAllFee() private {
        _taxFee = _previousTaxFee;
        _liquidityFee = _previousLiquidityFee;
    }

    // Function to check if an address is excluded from fees
    function isExcludedFromFee(address account) external view returns (bool) {
        return _isExcludedFromFee[account];
    }

    // Function to exclude an address from fees
    function excludeFromFee(address account) external onlyOwner {
        _isExcludedFromFee[account] = true;
    }

    // Function to include an address in fees
    function includeInFee(address account) external onlyOwner {
        _isExcludedFromFee[account] = false;
    }

    // Function to set the tax fee percentage
    function setTaxFeePercent(uint256 taxFee) external onlyOwner {
        _taxFee = taxFee;
    }

    // Function to set the liquidity fee percentage
    function setLiquidityFeePercent(uint256 liquidityFee) external onlyOwner {
        _liquidityFee = liquidityFee;
    }

    // Function to set the marketing address
    function setMarketingAddress(address _marketingAddress) external onlyOwner {
        marketingAddress = payable(_marketingAddress);
    }

    // Function to transfer ETH to a recipient
    function transferToAddressETH(address payable recipient, uint256 amount) private {
        recipient.transfer(amount);
    }

    // Function to check if an address is a confirmed sniper
    function isRemovedSniper(address account) external view returns (bool) {
        return _isSniper[account];
    }

    // Function to blacklist an address as a sniper
    function _removeSniper(address account) external onlyOwner {
        require(account != 0x10ED43C718714eb63d5aA57B78B54704E256024E, 'We can not blacklist Uniswap');
        require(!_isSniper[account], 'Account is already blacklisted');
        _isSniper[account] = true;
        _confirmedSnipers.push(account);
    }

    // Function to whitelist an address previously blacklisted as a sniper
    function _amnestySniper(address account) external onlyOwner {
        require(_isSniper[account], 'Account is not blacklisted');
        for (uint256 i = 0; i < _confirmedSnipers.length; i++) {
            if (_confirmedSnipers[i] == account) {
                _confirmedSnipers[i] = _confirmedSnipers[_confirmedSnipers.length - 1];
                _isSniper[account] = false;
                _confirmedSnipers.pop();
                break;
            }
        }
    }

    // Function to set the fee rate for liquidity provision
    function setFeeRate(uint256 rate) external onlyOwner {
        _feeRate = rate;
    }

    // Fallback function to receive ETH from Uniswap
    receive() external payable {}

    // Function to emergency withdraw ETH stuck in the contract
    function emergencyWithdraw() external onlyOwner {
        payable(owner()).send(address(this).balance);
    }
}
