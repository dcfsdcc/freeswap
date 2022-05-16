// SPDX-License-Identifier: GPL-3.0

pragma solidity >=0.5.0;
import '@pancakeswap/pancake-swap-lib/contracts/token/BEP20/IBEP20.sol';
import "../interfaces/IDCCSwapPair.sol";
import "../interfaces/IDCCSwapFactory.sol";
import "./DCCSwapSafeMath.sol";
import './DCCSwapLibrary.sol';
import '../interfaces/IDCCSwapRouter.sol';

library DCCSwapCallBackLibrary {
    using DCCSwapSafeMath for uint256;

    // returns sorted token addresses, used to handle return values from pairs sorted in this order
    
    
    function getFreePrice(IDCCSwapRouter router, address cakeAddress) public view returns (uint256 freePrice) {
        address factory = router.factory();
        (address token0ForCakeToDcc, address token1ForCakeToDcc) = DCCSwapLibrary.sortTokens(
            cakeAddress,
            router.WDCC()
        );
        if (IDCCSwapFactory(factory).getPair(token0ForCakeToDcc, token1ForCakeToDcc) != address(0)) {
            address pairAddressCakeDCC = IDCCSwapFactory(factory).getPair(token0ForCakeToDcc, token1ForCakeToDcc);
            (uint256 reserve0, uint256 reserve1, ) = IDCCSwapPair(pairAddressCakeDCC).getReserves();
            (uint256 reserveCake, uint256 reserveDCC) = cakeAddress == token0ForCakeToDcc
                ? (reserve0, reserve1)
                : (reserve1, reserve0);
            if (reserveCake > 0) {
                freePrice = reserveDCC.mul((10**uint256(IBEP20(cakeAddress).decimals()))).div(reserveCake);
            }
        }
    }

    function findPairByToken0Token1CakeAddress(IDCCSwapRouter router,  address tokenA, address tokenB,uint256 minDCCValueAllow,address cakeAddress) public view  returns (bool findPair) {
        findPair = false;
        address factory = router.factory();
        (address token0, address token1) = DCCSwapLibrary.sortTokens(tokenA, tokenB);
        if (IDCCSwapFactory(factory).getPair(token0, token1) != address(0)) {
            //不能直接找到，需要判断池子里的流动性有多少，太少了不能算
            //这里可能性是  wdcc/cake    token/cake
            if (token0 == router.WDCC() || token1 == router.WDCC()) {
                //当前LP 有dcc了，就不用转换，直接估值
                address wdccFreeLpAddress = IDCCSwapFactory(factory).getPair(token0, token1);
                (uint256 reserve0, uint256 reserve1, ) = IDCCSwapPair(wdccFreeLpAddress).getReserves();
                uint256 reserveWdcc = router.WDCC() == token0 ? reserve0 :  reserve1;
                //当前是dcc，余额乘以2 就是LP 总价值
                uint256 wdccValue = reserveWdcc.mul(2);
                // wdccValue0 = wdccValue;
                if (wdccValue > minDCCValueAllow) {
                    findPair = true;
                    
                }
            } else {
                //如果不是wdcc ，用 cake转换为dcc来评估
                address token0FreeLpAddress = IDCCSwapFactory(factory).getPair(token0, token1);
                (uint256 reserve0, uint256 reserve1, ) = IDCCSwapPair(token0FreeLpAddress).getReserves();
                uint256 reserveFree = cakeAddress == token0 ? reserve0 : reserve1;

                uint256 cakePrice = getFreePrice(router, cakeAddress);
                uint256 wdccValue = reserveFree.mul(cakePrice).div((10**uint256(IBEP20(router.WDCC()).decimals())));
                // wdccValue0 = wdccValue;
                if (wdccValue > minDCCValueAllow) {
                    findPair = true;
                }
            }
        }
    }

    function getTokenPriceByDcc(IDCCSwapRouter router,  address token0) public view returns (uint256 freePrice) {
        address factory = router.factory();
        (address token0ForCakeToDcc, address token1ForCakeToDcc) = DCCSwapLibrary.sortTokens(
            token0,
            router.WDCC()
        );
        if (IDCCSwapFactory(factory).getPair(token0ForCakeToDcc, token1ForCakeToDcc) != address(0)) {
            address pairAddressCakeDCC = IDCCSwapFactory(factory).getPair(token0ForCakeToDcc, token1ForCakeToDcc);
            (uint256 reserve0, uint256 reserve1, ) = IDCCSwapPair(pairAddressCakeDCC).getReserves();
            (uint256 reserveCake, uint256 reserveDCC) = token0 == token0ForCakeToDcc
                ? (reserve0, reserve1)
                : (reserve1, reserve0);
            if (reserveCake > 0) {
                freePrice = reserveDCC.mul((10**uint256(IBEP20(token0).decimals()))).div(reserveCake);
            }
        }
    }

    function computeDccValueByInputOutput(IDCCSwapRouter router, address input, address output, uint256 minDCCValueAllow) public view returns (bool findPair){
        findPair = false;
        address factory = router.factory();
         (address token0, address token1) = DCCSwapLibrary.sortTokens(input, output);
        if (token0 == router.WDCC() || token1 == router.WDCC()) {
            address wdccFreeLpAddress = IDCCSwapFactory(factory).getPair(token0, token1);
            if(wdccFreeLpAddress != address(0)){
                (uint256 reserve0, uint256 reserve1, ) = IDCCSwapPair(wdccFreeLpAddress).getReserves();
                uint256 reserveWdcc = router.WDCC() == token0 ? reserve0 :  reserve1;
                //当前是dcc，余额乘以2 就是LP 总价值
                uint256 wdccValue = reserveWdcc.mul(2);
                // wdccValue0 = wdccValue;
                if (wdccValue > minDCCValueAllow) {
                    findPair = true;
                }
            }
        } else {
            uint256 outputDccPrice = getTokenPriceByDcc(router, output);
            address wdccFreeLpAddress = IDCCSwapFactory(factory).getPair(token0, token1);
            if(wdccFreeLpAddress != address(0)){
                (uint256 reserve0, uint256 reserve1, ) = IDCCSwapPair(wdccFreeLpAddress).getReserves();
                uint256 reserveOutput = output == token0 ? reserve0 :  reserve1;
                uint256 reserveWdcc = reserveOutput.mul(outputDccPrice).div((10**uint256(IBEP20(router.WDCC()).decimals())));
                uint256 wdccValue = reserveWdcc.mul(2);
                // wdccValue0 = wdccValue;
                if (wdccValue > minDCCValueAllow) {
                    findPair = true;
                }
            } 
        }
    }

 

    


}
