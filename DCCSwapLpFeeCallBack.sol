pragma solidity >=0.5.0;

import "./interfaces/IDCCSwapLpFeeCallBack.sol";
import "./interfaces/IDCCSwapPair.sol";
import "./interfaces/IDCCSwapFactory.sol";
import '@pancakeswap/pancake-swap-lib/contracts/token/BEP20/IBEP20.sol';
import './interfaces/IDCCSwapRouter.sol';
import './libraries/DCCSwapLibrary.sol';
import './libraries/TransferHelper.sol';
import './interfaces/IWDCC.sol';

import './libraries/DCCSwapSafeMath.sol';

contract Context {
    // Empty internal constructor, to prevent people from mistakenly deploying
    // an instance of this contract, which should be used via inheritance.
    constructor() internal {}

    function _msgSender() internal view returns (address payable) {
        return msg.sender;
    }

    function _msgData() internal view returns (bytes memory) {
        this; // silence state mutability warning without generating bytecode - see https://github.com/ethereum/solidity/issues/2691
        return msg.data;
    }
}

contract Ownable is Context {
    address private _owner;

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    /**
     * @dev Initializes the contract setting the deployer as the initial owner.
     */
    constructor() internal {
        address msgSender = _msgSender();
        _owner = msgSender;
        emit OwnershipTransferred(address(0), msgSender);
    }

    /**
     * @dev Returns the address of the current owner.
     */
    function owner() public view returns (address) {
        return _owner;
    }

    /**
     * @dev Throws if called by any account other than the owner.
     */
    modifier onlyOwner() {
        require(_owner == _msgSender(), 'Ownable: caller is not the owner');
        _;
    }

    /**
     * @dev Leaves the contract without owner. It will not be possible to call
     * `onlyOwner` functions anymore. Can only be called by the current owner.
     *
     * NOTE: Renouncing ownership will leave the contract without an owner,
     * thereby removing any functionality that is only available to the owner.
     */
    function renounceOwnership() public onlyOwner {
        emit OwnershipTransferred(_owner, address(0));
        _owner = address(0);
    }

    /**
     * @dev Transfers ownership of the contract to a new account (`newOwner`).
     * Can only be called by the current owner.
     */
    function transferOwnership(address newOwner) public onlyOwner {
        _transferOwnership(newOwner);
    }

    /**
     * @dev Transfers ownership of the contract to a new account (`newOwner`).
     */
    function _transferOwnership(address newOwner) internal {
        require(newOwner != address(0), 'Ownable: new owner is the zero address');
        emit OwnershipTransferred(_owner, newOwner);
        _owner = newOwner;
    }
}

contract DCCSwapLpFeeCallBack is IDCCSwapLpFeeCallBack, Ownable {
    using DCCSwapSafeMath for uint256;
    
    address public factory;

    address public xOrigin;
    address public pairAddress;
    uint256 public feeAmount;

    uint256 public step;
    address public cakeAddress;
    IDCCSwapRouter public router;

    mapping(address => uint256) public freeAmountByPair;

    bool inSwapAndLiquify;
    modifier lockTheSwap() {
        inSwapAndLiquify = true;
        _;
        inSwapAndLiquify = false;
    }

    address public  feeTo;
    address public  feeToSetter;

    constructor(address _cake, IDCCSwapRouter _router) public {
        cakeAddress = _cake;
        router = _router;
        factory = router.factory();
    }
    function addFreeByPair(
        address pairAddressParam,
        uint256 freeAmount
    ) external override {
        address swapCallAddress = msg.sender;
        address swapFeeCallBackAddress = IDCCSwapFactory(factory).swapFeeCallBackAddress();
        require(swapCallAddress == swapFeeCallBackAddress , "DCCSwapLpFeeCallBack::addFreeByPair::SWAPCALL_INVALID_ADDRESS");

        freeAmountByPair[pairAddressParam] = freeAmountByPair[pairAddressParam] + freeAmount;
        
    }

    receive() external payable {}

    function AfterLpMintCallBack(
        uint256 _feeAmount
    ) external override{
        xOrigin = tx.origin;
        pairAddress = msg.sender;
        feeAmount = _feeAmount;
        address token0 = IDCCSwapPair(pairAddress).token0();
        address token1 = IDCCSwapPair(pairAddress).token1();
        
        uint256 cakeAmount = freeAmountByPair[pairAddress];//IBEP20(cakeAddress).balanceOf(address(pairAddress));
        (address token0Path, address token1Path) = DCCSwapLibrary.sortTokens(token0, token1);
        // getPairAddress = IDCCSwapFactory(factory).getPair(token0Path, token1Path);
        require(IDCCSwapFactory(factory).getPair(token0Path, token1Path) == pairAddress , "DCCSwapLpFeeCallBack::AfterLpMintCallBack::PAIR_INVALID_ADDRESS");
       

        if(cakeAmount>0){
            swapAndLiquifyByCake(token0, token1, cakeAmount, pairAddress);
            freeAmountByPair[pairAddress] = 0;
        }
    }

    function debugStep(
    uint256 _step
  ) external override{
        step = _step;
    }

    function setFactoryAddress(address _factoryAddress) public onlyOwner {
        factory = _factoryAddress;
    }

    function transferToken(address token, address to) public onlyOwner {
        require(token != address(0), "DCCSwapLpFeeCallBack::transferToken::TOKEN_ZERO_ADDRESS");
        require(to != address(0), "DCCSwapLpFeeCallBack::transferToken::TO_ZERO_ADDRESS");
        uint256 newBalanceToken0 = IBEP20(token).balanceOf(address(this));

        TransferHelper.safeTransfer(token, to, newBalanceToken0);
    }

    function transferDCC( address to) public onlyOwner {
        require(to != address(0), "DCCSwapLpFeeCallBack::transferToken::TO_ZERO_ADDRESS");
        uint256 newBalanceEth = address(this).balance;

        IWDCC(router.WDCC()).deposit{value: newBalanceEth}();
        assert(IWDCC(router.WDCC()).transfer(to, newBalanceEth));
    }

    function transferPair(address pair, address to, uint256 amount) public onlyOwner {
        require(pair != address(0), "DCCSwapLpFeeCallBack::transferPair::PAIR_ZERO_ADDRESS");
        require(to != address(0), "DCCSwapLpFeeCallBack::transferPair::TO_ZERO_ADDRESS");
        require(amount > 0, "DCCSwapLpFeeCallBack::transferPair::AMOUNT_ZERO");

        IDCCSwapPair(pair).transfer( to, amount);
    }

    function transferAllPair( address to) public onlyOwner {
        require(to != address(0), "DCCSwapLpFeeCallBack::transferAllPair::TO_ZERO_ADDRESS");
        uint256 allPairsLength = IDCCSwapFactory(factory).allPairsLength();
        for (uint256 i; i < allPairsLength - 1; i++) {
            address pairAddressTmp = IDCCSwapFactory(factory).allPairs(i);

            uint256 balance0 = IDCCSwapPair(pairAddressTmp).balanceOf(address(this));
            if (balance0 > 0)
            {
                IDCCSwapPair(pairAddressTmp).transfer(to, balance0);
            }

        }

    }

  function setFeeTo(address _feeTo) public   {
    require(msg.sender == feeToSetter, "DCCSwapLpFeeCallBack::setFeeTo::FORBIDDEN");
    feeTo = _feeTo;
  }

  function setFeeToSetter(address _feeToSetter) public onlyOwner {
    feeToSetter = _feeToSetter;
  }

    function receiveFee() public  {
        require(feeTo != address(0), "DCCSwapLpFeeCallBack::receiveFee::TO_ZERO_ADDRESS");
        uint256 allPairsLength = IDCCSwapFactory(factory).allPairsLength();
        for (uint256 i; i < allPairsLength - 1; i++) {
            address pairAddressTmp = IDCCSwapFactory(factory).allPairs(i);

            uint256 balance0 = IDCCSwapPair(pairAddressTmp).balanceOf(address(this));
            if (balance0 > 0)
            {
                IDCCSwapPair(pairAddressTmp).transfer(feeTo, balance0);
            }

        }

    }


    function swapAndLiquifyByCake(
        address token0,
        address token1,
        uint256 cakeTokenAmount,
        address to
    ) private lockTheSwap {
        // split the contract balance into halves
        uint256 half = cakeTokenAmount.div(2);
        uint256 otherHalf = cakeTokenAmount.sub(half);

        (address token0ForSwap, address token1ForSwap) = DCCSwapLibrary.sortTokens(token0, token1);


        if (IDCCSwapFactory(factory).getPair(token0ForSwap, token1ForSwap) != address(0)) {

            if (token0ForSwap == router.WDCC() || token1ForSwap == router.WDCC()) {

                if (token0ForSwap == cakeAddress || token1ForSwap == cakeAddress) {
                    //是 free ，直接转过去
                    TransferHelper.safeTransfer(cakeAddress, to, cakeTokenAmount);
                   
                } else {
                    // capture the contract's current ETH balance.
                    // this is so that we can capture exactly the amount of ETH that the
                    // swap creates, and not make the liquidity event include any ETH that
                    // has been manually sent to the contract
                    uint256 initialBalanceEth = address(this).balance;
                    // swap tokens for ETH
                    swapTokensForEth(cakeAddress, half);
                    // <- this breaks the ETH -> HATE swap when swap+liquify is triggered
                    // how much ETH did we just swap into?
                    uint256 newBalanceEth = address(this).balance.sub(initialBalanceEth);

                    address addToken = token0ForSwap == router.WDCC() ? token1ForSwap : token0ForSwap;
                    if (addToken != cakeAddress) {
                        //cake不用交易
                        // uint256 initialBalanceToken1 = IBEP20(addToken).balanceOf(address(this));
                        // swap tokens for Token  假设当前是 token1/dcc  ，需要 free => eth ,  token => dcc => token1,但是当前在 token1/dcc里，会存在锁问题
                        // 这种情况只能全部变成  eth 了
                        // swapTokensForToken(cakeAddress, addToken, otherHalf);
                        // uint256 newBalanceToken1 = IBEP20(addToken).balanceOf(address(this));
                        // otherHalf = newBalanceToken1.sub(initialBalanceToken1);
                        uint256 initialBalanceEth1 = address(this).balance;
                        swapTokensForEth(cakeAddress, otherHalf);
                        uint256 newBalanceEth1 = address(this).balance.sub(initialBalanceEth1);
                        IWDCC(router.WDCC()).deposit{value: newBalanceEth1}();
                        assert(IWDCC(router.WDCC()).transfer(to, newBalanceEth1));
                    } else {
                        //是 free ，直接转过去
                        TransferHelper.safeTransfer(addToken, to, otherHalf);
                    }
                    if ( newBalanceEth > 0) {
                        // add liquidity to uniswap
                        // addLiquidityETH(addToken, otherHalf, newBalanceEth, to);
                        IWDCC(router.WDCC()).deposit{value: newBalanceEth}();
                        assert(IWDCC(router.WDCC()).transfer(to, newBalanceEth));
                        
                    }
                }
            } else {
                if (token0ForSwap != cakeAddress && token1ForSwap != cakeAddress) {
                    //cake不用交易
                    uint256 initialBalanceToken0 = IBEP20(token0ForSwap).balanceOf(address(this));
                    // swap tokens for ETH
                    swapTokensForToken(cakeAddress, token0ForSwap, half);
                    uint256 newBalanceToken0 = IBEP20(token0ForSwap).balanceOf(address(this));
                    half = newBalanceToken0.sub(initialBalanceToken0);

                    //cake不用交易
                    uint256 initialBalanceToken1 = IBEP20(token1ForSwap).balanceOf(address(this));
                    // swap tokens for ETH
                    swapTokensForToken(cakeAddress, token1ForSwap, otherHalf);
                    uint256 newBalanceToken1 = IBEP20(token1ForSwap).balanceOf(address(this));
                    otherHalf = newBalanceToken1.sub(initialBalanceToken1);
                }
                if (token0ForSwap == cakeAddress || token1ForSwap == cakeAddress) {

                    //有一个是cake，就全部变成cake
                    token0ForSwap = cakeAddress;
                    token1ForSwap = cakeAddress;
                }
                if (half > 0 ) {
                    // add liquidity to uniswap
                    // addLiquidity(token0ForSwap, half, token1ForSwap, otherHalf, to);
                    TransferHelper.safeTransfer(token0ForSwap, to, half);
                }
                if (otherHalf > 0 ) {
                    // add liquidity to uniswap
                    // addLiquidity(token0ForSwap, half, token1ForSwap, otherHalf, to);
                    TransferHelper.safeTransfer(token1ForSwap, to, otherHalf);
                }
            }
        }

        //        emit SwapAndLiquify(half, newBalance, otherHalf);
    }



    function swapTokensForEth(address token, uint256 tokenAmount) private {
        // generate the uniswap pair path of token -> weth
        address[] memory path = new address[](2);
        path[0] = address(token);
        path[1] = router.WDCC();

        IBEP20(token).approve(address(router), tokenAmount);

        // make the swap
        router.swapExactTokensForETHSupportingFeeOnTransferTokens(
            tokenAmount,
            0, // accept any amount of ETH
            path,
            address(this),
            block.timestamp
        );
    }

    function swapTokensForToken(
        address token0,
        address token1,
        uint256 tokenAmount
    ) private {
        // generate the uniswap pair path of token -> weth
        address[] memory path = getPathForTokenByToken(token0, token1);
        // new address[](2);
        // path[0] = address(token0);
        // path[1] = address(token1);
        bool findPair = false;
        if (path.length == 2) {
            (address token0Path, address token1Path) = DCCSwapLibrary.sortTokens(path[0], path[1]);

            if (IDCCSwapFactory(factory).getPair(token0Path, token1Path) != address(0)) {
                findPair = true;
            }
        }
        if (path.length == 3) {
            (address token0Path, address token1Path) = DCCSwapLibrary.sortTokens(path[0], path[1]);
            (address token2Path, address token3Path) = DCCSwapLibrary.sortTokens(path[1], path[2]);

            if (
                IDCCSwapFactory(factory).getPair(token0Path, token1Path) != address(0) &&
                IDCCSwapFactory(factory).getPair(token2Path, token3Path) != address(0)
            ) {
                findPair = true;
            }
        }

        if (findPair) {
            IBEP20(token0).approve(address(router), tokenAmount);

            // make the swap
            router.swapExactTokensForTokensSupportingFeeOnTransferTokens(
                tokenAmount,
                0, // accept any amount of ETH
                path,
                address(this),
                block.timestamp
            );
        }
    }

    function getPathForTokenByToken(address token0, address token1) private view returns (address[] memory) {
        address[] memory path;
        if (token0 != router.WDCC() && token1 != router.WDCC()) {
            path = new address[](3);
            path[0] = token0;
            path[1] = router.WDCC();
            path[2] = token1;
        } else {
            path = new address[](2);
            path[0] = token0;
            path[1] = token1;
        }
        return path;
    }
}
