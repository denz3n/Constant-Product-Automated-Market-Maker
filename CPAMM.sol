// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

contract CPAMM {
    //takes in 2 tokens, immuatble bc will not change after we set tokens inside of constructor)
    IERC20 public immutable token0;
    IERC20 public immutable token1;

    //keep internal balance of two tokens in contract
    uint public reserve0;
    uint public reserve1;

    //need to mint or burn shares when user provides or removes liquidity//
    uint public totalSupply; //total share
    
    mapping(address => uint) public balanceOf; //share per user

    //const takes in addresses token0 and 1
    constructor(address _token0, address _token1) {
        token0 = IERC20(_token0);
        token1 = IERC20(_token1);
    }

    //internal func to mint shares, takes in address to mint to and amount
    function _mint(address _to, uint _amount) private {
        balanceOf[_to] += _amount;
        totalSupply += _amount;
    }

    //burn shares, opposite of mint
    function _burn(address _from, uint _amount) private {
        balanceOf[_from] -= _amount;
        totalSupply -= _amount;
    }

    //internal function to call in other funcs the user does
    function _update(uint _reserve0, uint _reserve1) private {
        reserve0 = _reserve0;
        reserve1 = _reserve1;
    }

    //                                                               //
    // The 3 funs user can call: swap, addliquidity, removeliquidity //
    //                                                               //

    /*
        FUNCTION OVERVIEW
        
        Users call <swap> to do trades for token0 => token1 or token1 => token0
        Pull in tokenIn
        Calculate tokenOut (include fees, 0.3%)
        Transfer token out to msg.sender
        Update the reserves
    */

    function swap(address _tokenIn, uint _amountIn) external returns (uint amountOut) {
        require(
            _tokenIn == address(token0) || _tokenIn == address(token1),  //ensure tokenIn is either token0 or token1
            "invalid token"
        );
        require(_amountIn > 0, "amount in = 0"); //ensure amountIn > 0

        bool isToken0 = _tokenIn == address(token0); //Determine if tokenIn is token0 or token1

        //declaring local vars
        (IERC20 tokenIn, IERC20 tokenOut, uint reserveIn, uint reserveOut) = isToken0 //if tokenIn is token0:
            ? (token0, token1, reserve0, reserve1) //then local vars tokenIn is token0, tokenOut is token1, resIn is res0, and resOut gets res1
            : (token1, token0, reserve1, reserve0); //but if tokenIn is token1, assign them oppositely

        //Pull in tokenIn
        tokenIn.transferFrom(msg.sender, address(this), _amountIn); //transfer token in to this contract

        //Calculate tokenOut
        /*
            Calculating amount out with constant product k
            How much dy for dx?
            y = reserveOut, x = reserveIn, dx = amountIn (with fee), SOLVE FOR dy = amountOut (with fee)

            xy = k
            (x + dx)(y - dy) = k
            y - dy = k / (x + dx)
            y - k / (x + dx) = dy
            y - xy / (x + dx) = dy
            (yx + ydx - xy) / (x + dx) = dy
            ydx / (x + dx) = dy
            reserveOut * amntInWithFees / (resIn + amntInWithFees)
        */

        uint amountInWithFee = (_amountIn * 997) / 1000;  // 0.3% fee
        amountOut = (reserveOut * amountInWithFee) / (reserveIn + amountInWithFee);

        //Transfer out
        tokenOut.transfer(msg.sender, amountOut); //transfer token out to msg sender

        //Update the reserves
        _update(token0.balanceOf(address(this)), token1.balanceOf(address(this)));
    }


    /*
        FUNCTION OVERVIEW
        
        Users call <addLiquidity> to provide two tokens into contract to add liquidity... this will mint shares to the user
        Pull in token0 and token 1
        Mint shares
        Update the reserves
    */

    function addLiquidity(uint _amount0, uint _amount1) external returns (uint shares) {

        //Pull in token0 and token1
        token0.transferFrom(msg.sender, address(this), _amount0);
        token1.transferFrom(msg.sender, address(this), _amount1);

        /*
            How much dx, dy to add?

            xy = k
            (x + dx)(y + dy) = k'

            No price change, before and after adding liquidity
            x / y = (x + dx) / (y + dy)

            x(y + dy) = y(x + dx)
            x * dy = y * dx

            x / y = dx / dy
            dy = y / x * dx
        */

        //if this check does not hold, then user able to change price by adding liquidity
        if (reserve0 > 0 || reserve1 > 0) {
            require(reserve0 * _amount1 == reserve1 * _amount0, "x / y != dx / dy"); //check that price is unchanged
        }

        /*
            How much shares to mint?

            f(x, y) = value of liquidity
            We will define f(x, y) = sqrt(xy)

            L0 = f(x, y)
            L1 = f(x + dx, y + dy)
            T = total shares
            s = shares to mint

            Total shares should increase proportional to increase in liquidity
            L1 / L0 = (T + s) / T

            L1 * T = L0 * (T + s)

            (L1 - L0) * T / L0 = s 
        */

        /*
            Claim
            (L1 - L0) / L0 = dx / x = dy / y

            Proof
            --- Equation 1 ---
            (L1 - L0) / L0 = (sqrt((x + dx)(y + dy)) - sqrt(xy)) / sqrt(xy)
            
            dx / dy = x / y so replace dy = dx * y / x

            --- Equation 2 ---
            Equation 1 = (sqrt(xy + 2ydx + dx^2 * y / x) - sqrt(xy)) / sqrt(xy)

            Multiply by sqrt(x) / sqrt(x)
            Equation 2 = (sqrt(x^2y + 2xydx + dx^2 * y) - sqrt(x^2y)) / sqrt(x^2y)
                    = (sqrt(y)(sqrt(x^2 + 2xdx + dx^2) - sqrt(x^2)) / (sqrt(y)sqrt(x^2))
            
            sqrt(y) on top and bottom cancels out

            --- Equation 3 ---
            Equation 2 = (sqrt(x^2 + 2xdx + dx^2) - sqrt(x^2)) / (sqrt(x^2)
            = (sqrt((x + dx)^2) - sqrt(x^2)) / sqrt(x^2)  
            = ((x + dx) - x) / x
            = dx / x

            Since dx / dy = x / y,
            dx / x = dy / y

            Finally
            (L1 - L0) / L0 = dx / x = dy / y
        */

        //calculating amount of shares to mint
        if (totalSupply == 0) {
            shares = _sqrt(_amount0 * _amount1);
        } else {
            shares = _min(
                (_amount0 * totalSupply) / reserve0,
                (_amount1 * totalSupply) / reserve1
            );
        }
        require(shares > 0, "shares = 0"); //check that amnt shares is >0

        //Minting shares
        _mint(msg.sender, shares);

        //Update reserves
        _update(token0.balanceOf(address(this)), token1.balanceOf(address(this)));
    }

    /*
        FUNCTION OVERVIEW
        
        Users call <removeLiquidity> to remove their tokens and fees that accrued from trade
        Determine amount0 and amount1 to withdraw (transfer back to user)
        Burn shares and update reserves
        Transfer tokens to msg sender
    */

    function removeLiquidity(
        uint _shares
    ) external returns (uint amount0, uint amount1) {
        /*
            Claim
            dx, dy = amount0 and amount1 of liquidity to remove
            dx = s / T * x
            dy = s / T * y

            Proof
            Let's find dx, dy such that
            v / L = s / T
            
            where
            v = f(dx, dy) = sqrt(dxdy)
            L = total liquidity = sqrt(xy)
            s = shares
            T = total supply

            --- Equation 1 ---
            v = s / T * L
            sqrt(dxdy) = s / T * sqrt(xy)

            Amount of liquidity to remove must not change price so 
            dx / dy = x / y

            replace dy = dx * y / x
            sqrt(dxdy) = sqrt(dx * dx * y / x) = dx * sqrt(y / x)

            Divide both sides of Equation 1 with sqrt(y / x)
            dx = s / T * sqrt(xy) / sqrt(y / x)
            = s / T * sqrt(x^2) = s / T * x

            Likewise
            dy = s / T * y
        */

        // bal0 >= reserve0
        // bal1 >= reserve1
        uint bal0 = token0.balanceOf(address(this));
        uint bal1 = token1.balanceOf(address(this));

        amount0 = (_shares * bal0) / totalSupply; //amount of tokens to go out
        amount1 = (_shares * bal1) / totalSupply;
        require(amount0 > 0 && amount1 > 0, "amount0 or amount1 = 0"); // >0 check

        //Burn shares of user
        _burn(msg.sender, _shares);

        //Update reserves
        _update(bal0 - amount0, bal1 - amount1);

        //Make transfers
        token0.transfer(msg.sender, amount0);
        token1.transfer(msg.sender, amount1);
    }

    //internal func to calculate sqrt
    function _sqrt(uint y) private pure returns (uint z) {
        if (y > 3) {
            z = y;
            uint x = y / 2 + 1;
            while (x < z) {
                z = x;
                x = (y / x + x) / 2;
            }
        } else if (y != 0) {
            z = 1;
        }
    }

    //internal func to return minimum of two numbers
    function _min(uint x, uint y) private pure returns (uint) {
        return x <= y ? x : y;
    }
}

//IERC20 interface whose funcs we call
interface IERC20 {
    function totalSupply() external view returns (uint);

    function balanceOf(address account) external view returns (uint);

    function transfer(address recipient, uint amount) external returns (bool);

    function allowance(address owner, address spender) external view returns (uint);

    function approve(address spender, uint amount) external returns (bool);

    function transferFrom(
        address sender,
        address recipient,
        uint amount
    ) external returns (bool);

    event Transfer(address indexed from, address indexed to, uint amount);
    event Approval(address indexed owner, address indexed spender, uint amount);
}
