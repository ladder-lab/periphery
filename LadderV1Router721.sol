pragma solidity =0.6.6;

import './libraries/TransferHelper.sol';

import './interfaces/ILadderV1Router721.sol';
import './libraries/LadderV1Library721.sol';
import './libraries/SafeMath.sol';
import './libraries/Initializable.sol';
import './interfaces/IERC20.sol';
import './interfaces/IWETH.sol';
import './interfaces/IERC1155.sol';
import './interfaces/IERC721.sol';


contract LadderV1Router721 is Initializable,ILadderV1Router721 {
    using SafeMath for uint;
    
    bytes4 private constant _INTERFACE_ID_ERC721 = 0x80ac58cd;

    address public override factory;
    address public override WETH;

    modifier ensure(uint deadline) {
        require(deadline >= block.timestamp, 'LadderV1Router721: EXPIRED');
        _;
    }

    function initialize(address _factory, address _WETH) public initializer {
        factory = _factory;
        WETH = _WETH;
    }

    receive() external payable {
        assert(msg.sender == WETH); // only accept ETH via fallback from the WETH contract
    }

    // **** ADD LIQUIDITY ****
    function _addLiquidity721(
        address token721,
        address tokenB,
        uint amount721,
        uint amountBDesired,
        uint amountBMin
    ) internal virtual returns (uint amountA, uint amountB) {
        require(IERC721(token721).supportsInterface(_INTERFACE_ID_ERC721),'token721 address must erc721 token');
        // create the pair if it doesn't exist yet
        if (ILadderV1Factory(factory).getPair(token721, tokenB) == address(0)) {
            ILadderV1Factory(factory).createPair(token721, tokenB);
        }
        (uint reserveA, uint reserveB) = LadderV1Library721.getReserves(factory, token721, tokenB);
        if (reserveA == 0 && reserveB == 0) {
            (amountA, amountB) = (amount721, amountBDesired);
        } else {
            uint amountBOptimal = LadderV1Library721.quote(amount721, reserveA, reserveB);
            require(amountBOptimal >= amountBMin && amountBOptimal <= amountBDesired, 'LadderV1Router721: INSUFFICIENT_B_AMOUNT');
            (amountA, amountB) = (amount721, amountBOptimal);
        }
    }
    
    function addLiquidity721(
        address token721,
        uint256[] calldata nftIds,
        address tokenB,
        uint amountBDesired,
        uint amountBMin,
        address to,
        uint deadline
    ) external virtual override ensure(deadline) returns (uint amountA, uint amountB, uint liquidity) {
        (amountA, amountB) = _addLiquidity721(token721, tokenB, nftIds.length, amountBDesired, amountBMin);
        address pair = LadderV1Library721.pairFor(factory, token721, tokenB);
        safeTransfer721(token721,msg.sender,address(pair),nftIds);
        TransferHelper.safeTransferFrom(tokenB, msg.sender, pair, amountB);
        liquidity = ILadderV1Pair721(pair).mint(to);
    }
    
    function addLiquidityETH721(
        address token721,
        uint256[] calldata nftIds,
        uint amount721,
        uint amountETHMin,
        address to,
        uint deadline
    ) external virtual override payable ensure(deadline) returns (uint amountToken, uint amountETH, uint liquidity) {
        require(amount721 == nftIds.length,'nftids length must equal to value');
        uint amountETHDesired = msg.value;
        (amountToken, amountETH) = _addLiquidity721(
            token721,
            WETH,
            amount721,
            amountETHDesired,
            amountETHMin
        );
        address pair = LadderV1Library721.pairFor(factory, token721, WETH);
        safeTransfer721(token721,msg.sender,address(pair),nftIds);
        IWETH(WETH).deposit{value: amountETH}();
        assert(IWETH(WETH).transfer(pair, amountETH));
        liquidity = ILadderV1Pair721(pair).mint(to);
        // refund dust eth, if any
        if (amountETHDesired > amountETH) TransferHelper.safeTransferETH(msg.sender, amountETHDesired - amountETH);
    }
    

    // **** REMOVE LIQUIDITY ****
    function removeLiquidity(
        address tokenA,
        address tokenB,
        uint liquidity,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline
    ) public virtual override ensure(deadline) returns (uint amountA, uint amountB) {
        address pair = LadderV1Library721.pairFor(factory, tokenA, tokenB);
        ILadderV1Pair721(pair).transferFrom(msg.sender, pair, liquidity); // send liquidity to pair
        (uint amount0, uint amount1,) = ILadderV1Pair721(pair).burn(to);
        (address token0,) = LadderV1Library721.sortTokens(tokenA, tokenB);
        (amountA, amountB) = tokenA == token0 ? (amount0, amount1) : (amount1, amount0);
        require(amountA >= amountAMin, 'LadderV1Router721: INSUFFICIENT_A_AMOUNT');
        require(amountB >= amountBMin, 'LadderV1Router721: INSUFFICIENT_B_AMOUNT');
    }
    function removeLiquidityETH(
        address token,
        uint liquidity,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline
    ) public virtual override ensure(deadline) returns (uint amountToken, uint amountETH) {
        address pair = LadderV1Library721.pairFor(factory, token, WETH);
        ILadderV1Pair721(pair).transferFrom(msg.sender, pair, liquidity); // send liquidity to pair
        (uint amount0, uint amount1,uint[] memory removeNFTIDs) = ILadderV1Pair721(pair).burn(address(this));
        (address token0,) = LadderV1Library721.sortTokens(token, WETH);
        (amountToken, amountETH) = token == token0 ? (amount0, amount1) : (amount1, amount0);
        require(amountToken >= amountTokenMin, 'LadderV1Router721: INSUFFICIENT_A_AMOUNT');
        require(amountETH >= amountETHMin, 'LadderV1Router721: INSUFFICIENT_B_AMOUNT');
        
        safeTransfer721(token,address(this),to,removeNFTIDs);
        IWETH(WETH).withdraw(amountETH);
        TransferHelper.safeTransferETH(to, amountETH);
    }
    function removeLiquidityWithPermit(
        address tokenA,
        address tokenB,
        uint liquidity,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline,
        bool approveMax, uint8 v, bytes32 r, bytes32 s
    ) external virtual override returns (uint amountA, uint amountB) {
        address pair = LadderV1Library721.pairFor(factory, tokenA, tokenB);
        uint value = approveMax ? uint(-1) : liquidity;
        ILadderV1Pair721(pair).permit(msg.sender, address(this), value, deadline, v, r, s);
        (amountA, amountB) = removeLiquidity(tokenA,tokenB, liquidity, amountAMin,amountBMin, to, deadline);
    }
    function removeLiquidityETHWithPermit(
        address token,
        uint liquidity,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline,
        bool approveMax, uint8 v, bytes32 r, bytes32 s
    ) external virtual override returns (uint amountToken, uint amountETH,uint[] memory removeNFTIDs) {
        address pair = LadderV1Library721.pairFor(factory, token, WETH);
        uint value = approveMax ? uint(-1) : liquidity;
        ILadderV1Pair721(pair).permit(msg.sender, address(this), value, deadline, v, r, s);
        (amountToken, amountETH) = removeLiquidityETH(token, liquidity, amountTokenMin, amountETHMin, to, deadline);
    }

  

    // **** SWAP ****
    // requires the initial amount to have already been sent to the first pair
    function _swap(uint[] memory amounts, uint[] memory changes, address[] memory path,uint[] memory erc721NFTIDs, address _to) internal virtual {
        require(path.length == 2,'path must only one pair');
        for (uint i; i < path.length - 1; i++) {
            (address input, address output) = (path[i], path[i + 1]);
            (address token0,) = LadderV1Library721.sortTokens(input, output);
            uint amountOut = amounts[i + 1];
            (uint amount0Out, uint amount1Out) = input == token0 ? (uint(0), amountOut) : (amountOut, uint(0));
            uint[] memory amountArr = new uint[](2);
            amountArr[0] = amount0Out;
            amountArr[1] = amount1Out;
            address to = i < path.length - 2 ? LadderV1Library721.pairFor(factory, output, path[i + 2]) : _to;
            ILadderV1Pair721(LadderV1Library721.pairFor(factory, input, output)).swap(
                amountArr, to, erc721NFTIDs,new bytes(0)
            );
            if (changes[i] > 0) {
                smartTransfer(input, _to, changes[i],erc721NFTIDs);
            }
        }
    }
    function swapExactTokensForTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        uint[] calldata erc721NFTIDs,
        address to,
        uint deadline
    ) external virtual override ensure(deadline) returns (uint[] memory amounts) {
        uint[] memory changes;
        (amounts, changes) = LadderV1Library721.getAmountsOut(factory, amountIn, path);
        require(amounts[amounts.length - 1] >= amountOutMin, 'LadderV1Router721: INSUFFICIENT_OUTPUT_AMOUNT');
        smartTransferFrom(path[0], msg.sender, LadderV1Library721.pairFor(factory, path[0], path[1]), amounts[0],erc721NFTIDs);
        _swap(amounts, changes, path,erc721NFTIDs ,to);
    }
    function swapTokensForExactTokens(
        uint amountOut,
        uint amountInMax,
        address[] calldata path,
        uint[] calldata erc721NFTIDs,
        address to,
        uint deadline
    ) external virtual override ensure(deadline) returns (uint[] memory amounts) {
        uint[] memory changes;
        (amounts, changes) = LadderV1Library721.getAmountsIn(factory, amountOut, path);
        require(amounts[0] <= amountInMax, 'LadderV1Router721: EXCESSIVE_INPUT_AMOUNT');
        smartTransferFrom(path[0], msg.sender, LadderV1Library721.pairFor(factory, path[0], path[1]), amounts[0],erc721NFTIDs);
        _swap(amounts, changes, path, erc721NFTIDs,to);
    }
    function swapExactETHForTokens(uint amountOutMin, address[] calldata path,uint[] calldata erc721NFTIDs, address to, uint deadline)
        external
        virtual
        override
        payable
        ensure(deadline)
        returns (uint[] memory amounts)
    {
        require(path[0] == WETH, 'LadderV1Router721: INVALID_PATH');
        uint[] memory changes;
        (amounts, changes) = LadderV1Library721.getAmountsOut(factory, msg.value, path);
        require(amounts[amounts.length - 1] >= amountOutMin, 'LadderV1Router721: INSUFFICIENT_OUTPUT_AMOUNT');
        IWETH(WETH).deposit{value: amounts[0]}();
        assert(IWETH(WETH).transfer(LadderV1Library721.pairFor(factory, path[0], path[1]), amounts[0]));
        _swap(amounts, changes, path, erc721NFTIDs,to);
    }
    function swapTokensForExactETH(uint amountOut, uint amountInMax, address[] calldata path,uint[] calldata erc721NFTIDs, address to, uint deadline)
        external
        virtual
        override
        ensure(deadline)
        returns (uint[] memory amounts)
    {
        require(path[path.length - 1] == WETH, 'LadderV1Router721: INVALID_PATH');
        uint[] memory changes;
        (amounts, changes) = LadderV1Library721.getAmountsIn(factory, amountOut, path);
        require(amounts[0] <= amountInMax, 'LadderV1Router721: EXCESSIVE_INPUT_AMOUNT');
        smartTransferFrom(path[0], msg.sender, LadderV1Library721.pairFor(factory, path[0], path[1]), amounts[0],erc721NFTIDs);
        _swap(amounts, changes, path,erc721NFTIDs, address(this));
        IWETH(WETH).withdraw(amounts[amounts.length - 1]);
        TransferHelper.safeTransferETH(to, amounts[amounts.length - 1]);
    }
    function swapExactTokensForETH(uint amountIn, uint amountOutMin, address[] calldata path,uint[] calldata erc721NFTIDs, address to, uint deadline)
        external
        virtual
        override
        ensure(deadline)
        returns (uint[] memory amounts)
    {
        require(path[path.length - 1] == WETH, 'LadderV1Router721: INVALID_PATH');
        uint[] memory changes;
        (amounts, changes) = LadderV1Library721.getAmountsOut(factory, amountIn, path);
        require(amounts[amounts.length - 1] >= amountOutMin, 'LadderV1Router721: INSUFFICIENT_OUTPUT_AMOUNT');
        smartTransferFrom(path[0], msg.sender, LadderV1Library721.pairFor(factory, path[0], path[1]), amounts[0],erc721NFTIDs);
        _swap(amounts, changes, path,erc721NFTIDs, address(this));
        IWETH(WETH).withdraw(amounts[amounts.length - 1]);
        TransferHelper.safeTransferETH(to, amounts[amounts.length - 1]);
    }
    function swapETHForExactTokens(uint amountOut, address[] calldata path,uint[] calldata erc721NFTIDs, address to, uint deadline)
        external
        virtual
        override
        payable
        ensure(deadline)
        returns (uint[] memory amounts)
    {
        require(path[0] == WETH, 'LadderV1Router721: INVALID_PATH');
        uint[] memory changes;
        (amounts, changes) = LadderV1Library721.getAmountsIn(factory, amountOut, path);
        require(amounts[0] <= msg.value, 'LadderV1Router721: EXCESSIVE_INPUT_AMOUNT');
        IWETH(WETH).deposit{value: amounts[0]}();
        assert(IWETH(WETH).transfer(LadderV1Library721.pairFor(factory, path[0], path[1]), amounts[0]));
        _swap(amounts, changes, path,erc721NFTIDs, to);
        // refund dust eth, if any
        if (msg.value > amounts[0]) TransferHelper.safeTransferETH(msg.sender, msg.value - amounts[0]);
    }



    function smartTransfer(
        address token,
        address to,
        uint256 value,
        uint[] memory erc721NFTIDs
    ) private {
        if (ILadderV1Factory(factory).isERC721(token)) {
            safeTransfer721(token,address(this),to,erc721NFTIDs);
        } else {
            TransferHelper.safeTransfer(token, to, value);
        }
    }

    function smartTransferFrom(
        address token,
        address from,
        address to,
        uint256 value,
        uint[] memory erc721NFTIDs
    ) private {
        if (ILadderV1Factory(factory).isERC721(token)) {
            safeTransfer721(token,from,to,erc721NFTIDs);
        } else {
            TransferHelper.safeTransferFrom(token, from, to, value);
        }
    }
    
    function safeTransfer721(address token,address from, address to,uint256[] memory erc721NFTIDs) private {
        for (uint256 i = 0; i < erc721NFTIDs.length; i++) {
            IERC721(token).safeTransferFrom(from,to,erc721NFTIDs[i]);
        } 
    }

    // **** LIBRARY FUNCTIONS ****
    function quote(uint amountA, uint reserveA, uint reserveB) public pure virtual override returns (uint amountB) {
        return LadderV1Library721.quote(amountA, reserveA, reserveB);
    }

    function getAmountOut(uint amountIn, uint reserveIn, uint reserveOut)
        public
        pure
        virtual
        override
        returns (uint amountOut)
    {
        return LadderV1Library721.getAmountOut(amountIn, reserveIn, reserveOut);
    }

    function getAmountIn(uint amountOut, uint reserveIn, uint reserveOut)
        public
        pure
        virtual
        override
        returns (uint amountIn)
    {
        return LadderV1Library721.getAmountIn(amountOut, reserveIn, reserveOut);
    }

    function getAmountsOut(uint amountIn, address[] memory path)
        public
        view
        virtual
        override
        returns (uint[] memory amounts)
    {
        (amounts,) = LadderV1Library721.getAmountsOut(factory, amountIn, path);
    }

    function getAmountsIn(uint amountOut, address[] memory path)
        public
        view
        virtual
        override
        returns (uint[] memory amounts)
    {
        (amounts,) = LadderV1Library721.getAmountsIn(factory, amountOut, path);
    }

    function smartBalanceOf(address token, address account) public view returns (uint256) {
        if (ILadderV1Factory(factory).isOriginERC1155(token)) {
            (address token1155, uint256 tokenId) = ILadderV1Factory(factory).getOriginInfo(token);
            return IERC1155(token1155).balanceOf(account, tokenId);
        } else {
            return IERC20(token).balanceOf(account);
        }
    }

    function onERC721Received(address operator,address from,uint256 tokenId,bytes calldata data) external returns (bytes4){
        return this.onERC721Received.selector;
    }
    
    
}
