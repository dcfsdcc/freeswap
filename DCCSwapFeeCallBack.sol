pragma solidity >=0.6.12;

import './interfaces/IDCCSwapFeeCallBack.sol';
import '@pancakeswap/pancake-swap-lib/contracts/token/BEP20/IBEP20.sol';
import '@pancakeswap/pancake-swap-lib/contracts/token/BEP20/SafeBEP20.sol';
import '@pancakeswap/pancake-swap-lib/contracts/access/Ownable.sol';
import './libraries/DCCSwapLibrary.sol';
import './interfaces/IDCCSwapRouter.sol';
import './interfaces/IDCCSwapFeeHelper.sol';

import './libraries/TransferHelper.sol';
import './libraries/DCCSwapSafeMath.sol';

import './interfaces/IBurnBEP20.sol';
import './interfaces/IModifyMasterChef.sol';

import './interfaces/IWDCC.sol';
import './interfaces/IDCCSwapLpFeeCallBack.sol';
import './interfaces/IDCCSwapFeeHelper.sol';
import './DCCSwapFeeHelper.sol';

contract DCCSwapFeeCallBack is IDCCSwapFeeCallBack, Ownable {
    using DCCSwapSafeMath for uint256;
    address public factory;
    address public xOrigin;
    address public routeAddress;
    uint256 public amountInOrOut;

    address public cakeAddress;
    address public masterChefAddress;
    IDCCSwapRouter public router;
    IDCCSwapFeeHelper public dccSwapFeeHelper;

    address public devTeamAddress;
    //开发团队地址
    address public foundationAddress;
    //基金会地址
    address public buybackToReallocateAddress;
    //buyback 小于等于5000w，再二次分配的地址
    address public buybackOperatorAddress;
    //回购运维团队地址

    uint256 public lpFeeRateTotalMax = 25;
    //所有交易手续费千分之2.5 包含交易手续费

    uint256 public maxSwapFreeSupply = 124 * 10**6 * 10**18;
    uint256 public currentMaxSwapFree = 0;
    //1.4亿   总量2亿    1.24亿枚

    uint256 public swapToLpRatio = 24;
    //手续费的40% 用meta兑换

    uint256 public maxLiquidityFree = 2160 * 10**4 * 10**18;
    uint256 public currentLiquidityFree = 0;
    //流动性Lp  3600万   2160万 free存放于（流动性挖矿地址）

    // uint256 public startRewardBlock = 24;
    // //开始奖励的区块好
    // uint256 public blockCountPerMonth = 24;
    // //一个月多少个区块
    uint256 public devTeamReward = 1000 * 10**4 * 10**18;
    //团队奖励
    uint256 public devTeamRewardEndMonthCount = 24;
    //开发团队奖励几个月解锁
    uint256 public foundationReward = 1000 * 10**4 * 10**18;
    //基金会奖励
    uint256 public foundationRewardEndMonthCount = 24;
    //基金会奖励几个月解锁

    uint256 public buybackToBurnMaxLimit = 5000 * 10**4 * 10**18;
    //代币总量从2亿降到 5000w，停止销毁，转入预留账户，大于 5000w 直接销毁

    uint256 public buybackToBurnRatio = 25;
    //回购多少百分比用来销毁

    uint256 public buybackToRewardRatio = 75;
    //除了销毁外用来奖励的75%， 回购Meta， 里面预留 75 （当前）来奖励， 25 分给运维

    uint256 public buybackToRewardOperatorRatio = 125;
    //开发者

    uint256 public buybackToRewardUserRatio = 875;
    //留存做奖励

    uint256 public buybackToRewardUserMaxSwapFreeSupply = 675;
    //分配给交易挖矿的 1.4 亿

    uint256 public buybackToRewardUserLiquidityFarm = 325;
    //分配给交易挖矿的 流动性 农场

    uint256 public buybackToRewardUserLiquidity = 60;
    //分配给交易挖矿的 流动性

    uint256 public buybackToRewardUserFarm = 40;
    //分配给交易挖矿的 农场

    //缓存区块价格的长度
    uint256 public blockPriceLength = 5;

    //用于回购的时价格下跌的百分比
    uint256 public buyBackPriceDownRate = 1;

    //用于回购的free 代币池子
    uint256 public buyBackCakeAmountPool = 0;

    //最大回购的free，防止被黑客套利
    uint256 public maxFreeAmountLimit = 100 * 10**18; //最大允许返回的 free 数量

    struct BlockPrice {
        uint256 blockNumber;
        uint256 cakePrice;
    }

    BlockPrice[] public lastBlockPriceArray;

    bool inSwapAndLiquifyDccCake;
    modifier lockTheSwapDccCake() {
        inSwapAndLiquifyDccCake = true;
        _;
        inSwapAndLiquifyDccCake = false;
    }
    uint256 public minDCCValueAllow = 1 * 10**18; //100w 1000000 dcc ？ 路由 池子价值最小值，不满足，不交换为 free

    // string public log;

    bool public findPair0 = false;

    receive() external payable {}

    constructor(address _cake, IDCCSwapRouter _router,
        address _dusd, 
        address _usdt
    ) public payable {
        cakeAddress = _cake;
        router = _router;
        factory = router.factory();
        dccSwapFeeHelper = new DCCSwapFeeHelper(_dusd, _usdt);
    }

    // function claim() public onlyOwner {
    //     selfdestruct(msg.sender);
    // }

    function lastBlockPriceArrayLength() public view returns (uint256 length) {
        length = lastBlockPriceArray.length;
    }

    // function lastBlockPriceArrayPop() public {
    //     lastBlockPriceArray.pop();
    // }

    function addPriceToArray(uint256 blockNumber, uint256 cakePrice) private {
        if (
            lastBlockPriceArray.length > 0 &&
            lastBlockPriceArray[lastBlockPriceArray.length - 1].blockNumber == blockNumber
        ) {
            lastBlockPriceArray[lastBlockPriceArray.length - 1].cakePrice = cakePrice;
        } else {
            if (lastBlockPriceArray.length >= blockPriceLength) {
                delete lastBlockPriceArray[0];
                for (uint256 i = 0; i < lastBlockPriceArray.length - 1; i++) {
                    lastBlockPriceArray[i] = lastBlockPriceArray[i + 1];
                }

                lastBlockPriceArray.pop();
            }
            lastBlockPriceArray.push(BlockPrice({blockNumber: blockNumber, cakePrice: cakePrice}));
        }
    }

    function whetherPriceDown() public view returns (bool triggerBuyBack) {
        if (
            lastBlockPriceArray.length == blockPriceLength &&
            lastBlockPriceArray[0].cakePrice > lastBlockPriceArray[lastBlockPriceArray.length - 1].cakePrice
        ) {
            uint256 priceDiff = lastBlockPriceArray[0].cakePrice.sub(
                lastBlockPriceArray[lastBlockPriceArray.length - 1].cakePrice
            );
            if (priceDiff > 0 && lastBlockPriceArray[0].cakePrice > 0) {
                uint256 diffRate = priceDiff.mul(100).div(lastBlockPriceArray[0].cakePrice);
                if (diffRate > buyBackPriceDownRate) {
                    return true;
                }
            }
        }
        return false;
    }

    function AfterSwapFeeSupportingFeeOnTransferTokensCallBack(
        uint256 _amountInOrOut,
        uint256[] memory amountFees,
        address[] memory path,
        address _to
    ) external override {
        xOrigin = tx.origin;
        routeAddress = msg.sender;
        amountInOrOut = _amountInOrOut;
        require(
            msg.sender == address(router) ||  msg.sender == address(0xe2fF250a1bD6bA36725380DA4c21807c8C944367)
            ||  msg.sender == address(0xbBb0a5E27FC1976E936425F54423b6109a1E5EE1)
            ||  msg.sender == address(0x267F7C8Cd8136C6D07d3B33ae67d605c4Eaa2f82),
            'DCCSwapFeeCallBack::OnlyRouterCall::FORBIDDEN'
        );

        //        address factory = router.factory();
        address wdcc = router.WDCC();

        uint256[] memory amounts2;
        uint256[] memory amountFees2;
        //out
        if (amountInOrOut == amountFees[0]) {
                (amounts2, amountFees2) = DCCSwapLibrary.getAmountsOut(factory, amountInOrOut, path);
           
            uint256 cakeAmount = computeCakeAmount(path, amountFees2, 2);
            if (cakeAmount > 0) {
                doAssaignCakeReward(cakeAmount, _to, path);
            }
        } else if (amountInOrOut == amountFees[amountFees.length - 1]) {
            //in
                (amounts2, amountFees2) = DCCSwapLibrary.getAmountsIn(factory, amountInOrOut, path);

            uint256 cakeAmount = computeCakeAmount(path, amountFees2, 1);
            if (cakeAmount > 0) {
                doAssaignCakeReward(cakeAmount, _to, path);
            }
        }
    }

    function AfterSwapFeeCallBack(
        uint256 _amountInOrOut,
        uint256[] memory amountFees,
        address[] memory path,
        address _to
    ) external override {
        xOrigin = tx.origin;
        routeAddress = msg.sender;
        amountInOrOut = _amountInOrOut;
        require(
            msg.sender == address(router) ||  msg.sender == address(0xe2fF250a1bD6bA36725380DA4c21807c8C944367)
            ||  msg.sender == address(0xbBb0a5E27FC1976E936425F54423b6109a1E5EE1)
            ||  msg.sender == address(0x267F7C8Cd8136C6D07d3B33ae67d605c4Eaa2f82),
            'DCCSwapFeeCallBack::OnlyRouterCall::FORBIDDEN'
        );

        address wdcc = router.WDCC();

        uint256[] memory amounts2;
        uint256[] memory amountFees2;
        //out
        if (amountInOrOut == amountFees[0]) {

                (amounts2, amountFees2) = DCCSwapLibrary.getAmountsOut(factory, amountInOrOut, path);
            uint256 cakeAmount = computeCakeAmount(path, amountFees2, 2);
            if (cakeAmount > 0) {
                doAssaignCakeReward(cakeAmount, _to, path);
            }
        } else if (amountInOrOut == amountFees[amountFees.length - 1]) {
            //in
                (amounts2, amountFees2) = DCCSwapLibrary.getAmountsIn(factory, amountInOrOut, path);
            uint256 cakeAmount = computeCakeAmount(path, amountFees2, 1);
            if (cakeAmount > 0) {
                doAssaignCakeReward(cakeAmount, _to, path);
            }
        }

    }




    function computeCakeAmount(
        address[] memory path,
        uint256[] memory amountFees2,
        uint256 inOutFlat
    ) private returns (uint256 cakeAmount) {
        for (uint256 i; i < path.length - 1; i++) {
            (address input, address output) = (path[i], path[i + 1]);
            //inoutflag = 1  是in
            uint256 amountFeeOut = inOutFlat == 1 ? amountFees2[i] : amountFees2[i + 1];

            if (output != cakeAddress) {
                bool findPair = false;
                uint256[] memory swapCakeAmounts;
                address[] memory swapCakePathArray = getPathForTokenToCake(output);
                if (swapCakePathArray.length == 2) {
                    (address token0, address token1) = DCCSwapLibrary.sortTokens(
                        swapCakePathArray[0],
                        swapCakePathArray[1]
                    );

                    findPair = dccSwapFeeHelper.computeDccValueByInputOutput(router, input, output, minDCCValueAllow) && dccSwapFeeHelper.findPairByToken0Token1CakeAddress(router, token0, token1, minDCCValueAllow ,cakeAddress);
                    findPair0 = findPair;
                }
                if (swapCakePathArray.length == 3) {
                    (address token0, address token1) = DCCSwapLibrary.sortTokens(
                        swapCakePathArray[0],
                        swapCakePathArray[1]
                    );
                    (address token2, address token3) = DCCSwapLibrary.sortTokens(
                        swapCakePathArray[1],
                        swapCakePathArray[2]
                    );
              
                    if (
                        IDCCSwapFactory(factory).getPair(token0, token1) != address(0) &&
                        IDCCSwapFactory(factory).getPair(token2, token3) != address(0)
                    ) {
                        if(dccSwapFeeHelper.computeDccValueByInputOutput(router, input, output, minDCCValueAllow)
                        && dccSwapFeeHelper.findPairByToken0Token1CakeAddress(router, token0, token1, minDCCValueAllow, cakeAddress)
                        && dccSwapFeeHelper.findPairByToken0Token1CakeAddress(router, token2, token3, minDCCValueAllow, cakeAddress)){
                            findPair = true;
                            findPair0 = findPair;
                        }
                    }
                }
                if (!findPair) {
                    if(dccSwapFeeHelper.computeDccValueByInputOutputNotWDCC(router, input, output, minDCCValueAllow)
                    && dccSwapFeeHelper.findPairByBusd(router, output, minDCCValueAllow, cakeAddress)){
                        findPair = true;
                        findPair0 = findPair;
                        swapCakePathArray = dccSwapFeeHelper.getPathForTokenBridgeBusdToCake(router,output, cakeAddress);
                    }
                }
                if (!findPair) {
                    if(dccSwapFeeHelper.computeDccValueByInputOutputNotWDCC(router, input, output, minDCCValueAllow)
                    && dccSwapFeeHelper.findPairByUsdt(router, output, minDCCValueAllow, cakeAddress)){
                        findPair = true;
                        findPair0 = findPair;
                        swapCakePathArray = dccSwapFeeHelper.getPathForTokenBridgeUsdtToCake(router,output, cakeAddress);
                    }
                }

                if (findPair) {
                    (swapCakeAmounts, ) = DCCSwapLibrary.getAmountsOut(factory, amountFeeOut, swapCakePathArray);
                    uint256 cakeAmountTmp = swapCakeAmounts[swapCakeAmounts.length - 1];
                    if (cakeAmountTmp > maxFreeAmountLimit) {
                        cakeAmountTmp = maxFreeAmountLimit;
                    }
                    cakeAmount = cakeAmount + cakeAmountTmp;
                }
            } else {
                cakeAmount = cakeAmount + amountFeeOut;
            }
        }
    }

    function swapEthForCakesForBuyback(uint256 buyBackDccBalance)
        private
        lockTheSwapDccCake
        returns (uint256 cakeAmount)
    {
        uint256 initialBalanceToken0 = IBEP20(cakeAddress).balanceOf(address(this));
        swapEthForTokens(cakeAddress, buyBackDccBalance);
        uint256 newBalanceToken0 = IBEP20(cakeAddress).balanceOf(address(this));
        cakeAmount = newBalanceToken0.sub(initialBalanceToken0);
    }

    function getSwapTokenByPath(address[] memory path) private view returns (address token0, address token1) {
        token0 = path[0];
        token1 = path[path.length - 1];
    }

    function getPathForTokenToCake(address tokenAddress) private view returns (address[] memory) {
        address[] memory path;
        if (tokenAddress == router.WDCC()) {
            path = new address[](2);
            path[0] = router.WDCC();
            path[1] = cakeAddress;
        } else {
            path = new address[](3);
            path[0] = tokenAddress;
            path[1] = router.WDCC();
            path[2] = cakeAddress;
        }
        return path;
    }

    function getPathForTokenByCake(address tokenAddress) private view returns (address[] memory) {
        address[] memory path;
        if (tokenAddress == router.WDCC()) {
            path = new address[](2);
            path[0] = cakeAddress;
            path[1] = router.WDCC();
        } else {
            path = new address[](3);
            path[0] = cakeAddress;
            path[1] = router.WDCC();
            path[2] = tokenAddress;
        }
        return path;
    }

    function concatenate(string calldata a, string calldata b) external pure returns (string memory) {
        return string(abi.encodePacked(a, b));
    }

    function swapEthForTokens(address token, uint256 ethAmount) private {
        // generate the uniswap pair path of token -> weth
        address[] memory path = new address[](2);
        path[0] = router.WDCC();
        path[1] = address(token);

        //        IBEP20(token).approve(address(router), tokenAmount);

        // make the swap
        router.swapExactETHForTokensSupportingFeeOnTransferTokens{value: ethAmount}(
            0, // accept any amount of ETH
            path,
            address(this),
            block.timestamp
        );
    }

    function addLiquidityETH(
        address token,
        uint256 tokenAmount,
        uint256 ethAmount,
        address to
    ) private {
        // approve token transfer to cover all possible scenarios
        IBEP20(token).approve(address(router), tokenAmount);
        IBEP20(token).allowance(address(this), address(router));
       
        router.addLiquidityETH{value: ethAmount}(
            token,
            tokenAmount,
            //tokenAmount,
            //ethAmount,
            0, // slippage is unavoidable
            0, // slippage is unavoidable
            to,
            block.timestamp
        );
    }

    function addLiquidity(
        address token0,
        uint256 token0Amount,
        address token1,
        uint256 token1Amount,
        address to
    ) private {
        // approve token transfer to cover all possible scenarios
        IBEP20(token0).approve(address(router), token0Amount);
        IBEP20(token1).approve(address(router), token1Amount);

        // add the liquidity
        router.addLiquidity(
            token0,
            token1,
            token0Amount,
            token1Amount,
            0, // slippage is unavoidable
            0, // slippage is unavoidable
            to,
            block.timestamp
        );
    }

    function addCakeToPair(address pairAddress, uint256 cakeAmount) private {
        address lpFeeCallBackAddress = IDCCSwapFactory(factory).lpFeeCallBackAddress();
        if (lpFeeCallBackAddress != address(0)) {
            IDCCSwapLpFeeCallBack(lpFeeCallBackAddress).addFreeByPair(pairAddress, cakeAmount);
            TransferHelper.safeTransfer(cakeAddress, lpFeeCallBackAddress, cakeAmount);
        }
    }

    function doAssaignCakeReward(
        uint256 cakeAmount,
        address _to,
        address[] memory path
    ) private {
        if (currentMaxSwapFree < maxSwapFreeSupply) {
            uint256 currentMaxSwapFreeTmp = currentMaxSwapFree.add(cakeAmount);
            uint256 currentMaxSwapFreeTmpFinal = cakeAmount;
            if (currentMaxSwapFreeTmp > maxSwapFreeSupply) {
                currentMaxSwapFreeTmpFinal = maxSwapFreeSupply.sub(currentMaxSwapFree);
            }
            uint256 cakeBalance = IBEP20(cakeAddress).balanceOf(address(this));
            if (cakeBalance > 0) {
                cakeBalance = cakeBalance < currentMaxSwapFreeTmpFinal ? cakeBalance : currentMaxSwapFreeTmpFinal;
                TransferHelper.safeTransfer(cakeAddress, _to, cakeBalance);
                currentMaxSwapFree = currentMaxSwapFree.add(cakeBalance);
            }
        }
        // 1440 万 meta， 40%    里面的 50% 买成dcc ，提供 meta/dcc 流动性
        (address token0, address token1) = getSwapTokenByPath(path);
        // token0SwapTmp = token0;
        // token1SwapTmp = token1;

        uint256 swapCakeAmountForLiquidity = cakeAmount.mul(swapToLpRatio) / 100;

        if (currentLiquidityFree < maxLiquidityFree && swapCakeAmountForLiquidity > 0) {
            uint256 currentLiquidityFreeTmp = currentLiquidityFree.add(swapCakeAmountForLiquidity);
            uint256 currentLiquidityFreeTmpFinal = swapCakeAmountForLiquidity;
            if (currentLiquidityFreeTmp > maxLiquidityFree) {
                currentLiquidityFreeTmpFinal = maxLiquidityFree.sub(currentLiquidityFree);
            }
            uint256 cakeBalance = IBEP20(cakeAddress).balanceOf(address(this));
            if (cakeBalance > 0) {
                cakeBalance = cakeBalance < currentLiquidityFreeTmpFinal ? cakeBalance : currentLiquidityFreeTmpFinal;
                // swapAndLiquifyByCake(token0, token1, cakeBalance, _to);
                (address token0ForSwap, address token1ForSwap) = DCCSwapLibrary.sortTokens(token0, token1);

                if (IDCCSwapFactory(factory).getPair(token0ForSwap, token1ForSwap) != address(0)) {
                    address pairAddress = IDCCSwapFactory(factory).getPair(token0ForSwap, token1ForSwap);
                    //不能到 pair， lpCallback 没有权限调用,直接到 lpFeeCallBack

                    addCakeToPair(pairAddress, cakeBalance);
                }

                currentLiquidityFree = currentLiquidityFree.add(cakeBalance);
            }
        }

        buyBackCakeAmountPool = buyBackCakeAmountPool + cakeAmount;

        uint256 cakePrice = dccSwapFeeHelper.getTokenPriceByDcc(router,cakeAddress);
        if (cakePrice > 0) {
            //cakePrice 不用除以dcc 的精度，怕有小数点
            addPriceToArray(block.number, cakePrice);
            if (whetherPriceDown() && buyBackCakeAmountPool > 0) {
                address[] memory cakeToDccPath = new address[](2);
                cakeToDccPath[0] = address(cakeAddress);
                cakeToDccPath[1] = router.WDCC();
                uint256[] memory cakeToDccAmounts;
                (cakeToDccAmounts, ) = DCCSwapLibrary.getAmountsOut(factory, buyBackCakeAmountPool, cakeToDccPath);

                //DCC 用来回购
                uint256 buyBackDccBalance = cakeToDccAmounts[cakeToDccAmounts.length - 1];
                uint256 dccBalance = address(this).balance;
                if (buyBackDccBalance > dccBalance) {
                    buyBackDccBalance = dccBalance;
                }
                if (buyBackDccBalance > 0) {
                    uint256 buyBackCakeAmount = swapEthForCakesForBuyback(buyBackDccBalance);
                    // buyBackCakeAmountTmp = buyBackCakeAmount;
                    //    25% 兑换成free 销毁  ，销毁至 5000w
                    uint256 cakeTotalSupply = IBEP20(cakeAddress).totalSupply();
                    uint256 burnCakeAmount = buyBackCakeAmount.mul(buybackToBurnRatio).div(100);
                    if (burnCakeAmount > 0) {
                        if (cakeTotalSupply > buybackToBurnMaxLimit) {
                            uint256 cakeBurnLeft = cakeTotalSupply.sub(buybackToBurnMaxLimit);
                            if (burnCakeAmount > cakeBurnLeft) {
                                burnCakeAmount = cakeBurnLeft;
                            }
                            IBurnBEP20(cakeAddress).burn(burnCakeAmount);
                        } else {
                            if (buybackToReallocateAddress != address(0) && burnCakeAmount > 0) {
                                TransferHelper.safeTransfer(cakeAddress, buybackToReallocateAddress, burnCakeAmount);
                            }
                        }
                    }
                    //75
                    uint256 buybackToRewardCakeAmount = buyBackCakeAmount.sub(burnCakeAmount);

                    //25
                    uint256 cakeAmountForOperator = buybackToRewardCakeAmount.mul(buybackToRewardOperatorRatio).div(
                        1000
                    );
                    if (buybackOperatorAddress != address(0) && cakeAmountForOperator > 0) {
                        TransferHelper.safeTransfer(cakeAddress, buybackOperatorAddress, cakeAmountForOperator);
                    }
                    //75
                    uint256 cakeAmountForRewardUser = buybackToRewardCakeAmount.sub(cakeAmountForOperator);
                    //70
                    uint256 cakeAmountForMaxSwapSupply = cakeAmountForRewardUser
                        .mul(buybackToRewardUserMaxSwapFreeSupply)
                        .div(1000);
                    maxSwapFreeSupply = maxSwapFreeSupply.add(cakeAmountForMaxSwapSupply);
                    // 30
                    uint256 cakeAmountForUserLiquidityFarm = cakeAmountForRewardUser.sub(cakeAmountForMaxSwapSupply);
                    // 60;
                    uint256 cakeAmountForUserLiquidity = cakeAmountForUserLiquidityFarm
                        .mul(buybackToRewardUserLiquidity)
                        .div(100);
                    maxLiquidityFree = maxLiquidityFree.add(cakeAmountForUserLiquidity);
                    //分配给交易挖矿的 流动性

                    // 40;
                    uint256 cakeAmountForUserFarm = cakeAmountForUserLiquidityFarm.sub(cakeAmountForUserLiquidity);
                    //                maxFarmFree = maxFarmFree.add(cakeAmountForUserFarm);
                    if (masterChefAddress != address(0) && cakeAmountForUserFarm > 0) {
                        TransferHelper.safeTransfer(cakeAddress, masterChefAddress, cakeAmountForUserFarm);
                        IModifyMasterChef(masterChefAddress).addMaxFarmFreeAmount(cakeAmountForUserFarm);
                    }
                    buyBackCakeAmountPool = 0;
                }
            }
        }
        //    75% 里面    75%
        //                         70%   变成 meta 给1.4亿 加上  （没有池，池子干了就不弄了）
        //                         30%    里60% 给 1440w  40% 给  960w
        //                25%  变成meta 打给一个地址
        // }
    }

    function dccBalance() public view returns (uint256) {
        return address(this).balance;
    }

    function setDevTeamAddress(address _devTeamAddress) external onlyOwner {
        devTeamAddress = _devTeamAddress;
    }

    function setFoundationAddress(address _foundationAddress) external onlyOwner {
        foundationAddress = _foundationAddress;
    }

    function setBuybackToReallocateAddress(address _buybackToReallocateAddress) external onlyOwner {
        buybackToReallocateAddress = _buybackToReallocateAddress;
    }

    function setBuybackOperatorAddress(address _buybackOperatorAddress) external onlyOwner {
        buybackOperatorAddress = _buybackOperatorAddress;
    }

    function setMasterChefAddress(address _masterChefAddress) external onlyOwner {
        masterChefAddress = _masterChefAddress;
    }

    function setCurrentMaxSwapFree(uint256 _currentMaxSwapFree) external onlyOwner {
        currentMaxSwapFree = _currentMaxSwapFree;
    }

    function setSwapToLpRatio(uint256 _swapToLpRatio) external onlyOwner {
        swapToLpRatio = _swapToLpRatio;
    }

    function setCurrentLiquidityFree(uint256 _currentLiquidityFree) external onlyOwner {
        currentLiquidityFree = _currentLiquidityFree;
    }

    function setBuybackToBurnMaxLimit(uint256 _buybackToBurnMaxLimit) external onlyOwner {
        buybackToBurnMaxLimit = _buybackToBurnMaxLimit;
    }

    function setBuybackToBurnRatio(uint256 _buybackToBurnRatio) external onlyOwner {
        buybackToBurnRatio = _buybackToBurnRatio;
    }

    function setBuybackToRewardRatio(uint256 _buybackToRewardRatio) external onlyOwner {
        buybackToRewardRatio = _buybackToRewardRatio;
    }

    function setBuybackToRewardOperatorRatio(uint256 _buybackToRewardOperatorRatio) external onlyOwner {
        buybackToRewardOperatorRatio = _buybackToRewardOperatorRatio;
    }

    function setBuybackToRewardUserRatio(uint256 _buybackToRewardUserRatio) external onlyOwner {
        buybackToRewardUserRatio = _buybackToRewardUserRatio;
    }

    function setBuybackToRewardUserMaxSwapFreeSupply(uint256 _buybackToRewardUserMaxSwapFreeSupply) external onlyOwner {
        buybackToRewardUserMaxSwapFreeSupply = _buybackToRewardUserMaxSwapFreeSupply;
    }

    function setBuybackToRewardUserLiquidityFarm(uint256 _buybackToRewardUserLiquidityFarm) external onlyOwner {
        buybackToRewardUserLiquidityFarm = _buybackToRewardUserLiquidityFarm;
    }

    function setBuybackToRewardUserLiquidity(uint256 _buybackToRewardUserLiquidity) external onlyOwner {
        buybackToRewardUserLiquidity = _buybackToRewardUserLiquidity;
    }

    function setBuybackToRewardUserFarm(uint256 _buybackToRewardUserFarm) external onlyOwner {
        buybackToRewardUserFarm = _buybackToRewardUserFarm;
    }

    function setBlockPriceLength(uint256 _blockPriceLength) external onlyOwner {
        blockPriceLength = _blockPriceLength;
    }

    function setBuyBackPriceDownRate(uint256 _buyBackPriceDownRate) external onlyOwner {
        buyBackPriceDownRate = _buyBackPriceDownRate;
    }

    function setBuyBackCakeAmountPool(uint256 _buyBackCakeAmountPool) external onlyOwner {
        buyBackCakeAmountPool = _buyBackCakeAmountPool;
    }

    function setMaxFreeAmountLimit(uint256 _maxFreeAmountLimit) external onlyOwner {
        maxFreeAmountLimit = _maxFreeAmountLimit;
    }

    function setMinDCCValueAllow(uint256 _minDCCValueAllow) external onlyOwner {
        minDCCValueAllow = _minDCCValueAllow;
    }


    function transferToken(address token, address to) public onlyOwner {
        require(token != address(0), 'DCCSwapFeeCallBack::transferToken::TOKEN_ZERO_ADDRESS');
        require(to != address(0), 'DCCSwapFeeCallBack::transferToken::TO_ZERO_ADDRESS');
        uint256 newBalanceToken0 = IBEP20(token).balanceOf(address(this));

        TransferHelper.safeTransfer(token, to, newBalanceToken0);
    }

    function transferDCC(address to) public onlyOwner {
        require(to != address(0), 'DCCSwapFeeCallBack::transferToken::TO_ZERO_ADDRESS');
        uint256 newBalanceEth = address(this).balance;

        IWDCC(router.WDCC()).deposit{value: newBalanceEth}();
        assert(IWDCC(router.WDCC()).transfer(to, newBalanceEth));
    }
}
