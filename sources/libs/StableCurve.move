/// Implements stable curve math.
module MultiSwap::StableCurve {
    // !!!FOR AUDITOR!!!
    // Please, review this file really carefully and detailed.
    // Some of the functions just migrated from Solidly (BaseV1-core).
    // Some we implemented outself, like coin_in, dx.
    // Also look at all places in all contracts where the functions called and check places too and arguments.
    use U256::U256::{Self, U256};

    /// We take 10^8 as we expect most of the coins to have 6-8 decimals.
    const ONE_E_8: u128 = 100000000;

    /// Get LP value for stable curve: x^3*y + x*y^3
    /// * `x_coin` - reserves of coin X.
    /// * `x_scale` - 10 pow X coin decimals amount.
    /// * `y_coin` - reserves of coin Y.
    /// * `y_scale` - 10 pow Y coin decimals amount.
    public fun lp_value(x_coin: u128, x_scale: u64, y_coin: u128, y_scale: u64): U256 {
        let x_u256 = U256::from_u128(x_coin);
        let y_u256 = U256::from_u128(y_coin);
        let u2561e8 = U256::from_u128(ONE_E_8);

        let x_scale_u256 = U256::from_u64(x_scale);
        let y_scale_u256 = U256::from_u64(y_scale);

        let _x = U256::div(
            U256::mul(x_u256, u2561e8),
            x_scale_u256,
        );

        let _y = U256::div(
            U256::mul(y_u256, u2561e8),
            y_scale_u256,
        );

        let _a = U256::div(
            U256::mul(_x, _y),
            u2561e8,
        );

        // ((_x * _x) / 1e18 + (_y * _y) / 1e18)
        let _b = U256::add(
            U256::div(
                U256::mul(_x, _x),
                u2561e8,
            ),
            U256::div(
                U256::mul(_y, _y),
                u2561e8,
            )
        );

        U256::div(
            U256::mul(_a, _b),
            u2561e8,
        )
    }

    /// Get coin amount out by passing amount in, returns amount out (we don't take fees into account here).
    /// It probably would eat a lot of gas and better to do it offchain (on your frontend or whatever),
    /// yet if no other way and need blockchain computation we left it here.
    /// * `coin_in` - amount of coin to swap.
    /// * `scale_in` - 10 pow by coin decimals you want to swap.
    /// * `scale_out` - 10 pow by coin decimals you want to get.
    /// * `reserve_in` - reserves of coin to swap coin_in.
    /// * `reserve_out` - reserves of coin to get in exchange.
    public fun coin_out(coin_in: u128, scale_in: u64, scale_out: u64, reserve_in: u128, reserve_out: u128): u128 {
        let u2561e8 = U256::from_u128(ONE_E_8);

        let xy = lp_value(reserve_in, scale_in, reserve_out, scale_out);
        let reserve_in_u256 = U256::div(
            U256::mul(
                U256::from_u128(reserve_in),
                u2561e8,
            ),
            U256::from_u64(scale_in),
        );
        let reserve_out_u256 = U256::div(
            U256::mul(
                U256::from_u128(reserve_out),
                u2561e8,
            ),
            U256::from_u64(scale_out),
        );
        let amountIn = U256::div(
            U256::mul(
                U256::from_u128(coin_in),
                u2561e8
            ),
            U256::from_u64(scale_in)
        );
        let total_reserve = U256::add(amountIn, reserve_in_u256);
        let y = U256::sub(
            reserve_out_u256,
            get_y(total_reserve, xy, reserve_out_u256),
        );

        let r = U256::div(
            U256::mul(
                y,
                U256::from_u64(scale_out),
            ),
            u2561e8
        );

        U256::as_u128(r)
    }

    /// Get coin amount in by passing amount out, returns amount in (we don't take fees into account here).
    /// It probably would eat a lot of gas and better to do it offchain (on your frontend or whatever),
    /// yet if no other way and need blockchain computation we left it here.
    /// * `coin_out` - amount of coin you want to get.
    /// * `scale_in` - 10 pow by coin decimals you want to swap.
    /// * `scale_out` - 10 pow by coin decimals you want to get.
    /// * `reserve_in` - reserves of coin to swap.
    /// * `reserve_out` - reserves of coin to get in exchange.
    public fun coin_in(coin_out: u128, scale_out: u64, scale_in: u64, reserve_out: u128, reserve_in: u128): u128 {
        let u2561e8 = U256::from_u128(ONE_E_8);

        let xy = lp_value(reserve_in, scale_in, reserve_out, scale_out);
        let reserve_in_u256 = U256::div(
            U256::mul(
                U256::from_u128(reserve_in),
                u2561e8,
            ),
            U256::from_u64(scale_in),
        );
        let reserve_out_u256 = U256::div(
            U256::mul(
                U256::from_u128(reserve_out),
                u2561e8,
            ),
            U256::from_u64(scale_out),
        );
        let amountOut = U256::div(
            U256::mul(
                U256::from_u128(coin_out),
                u2561e8
            ),
            U256::from_u64(scale_out)
        );

        let total_reserve = U256::sub(reserve_out_u256, amountOut);
        let x = U256::sub(
            get_x(total_reserve, xy, reserve_in_u256),
            reserve_in_u256,
        );
        let r = U256::div(
            U256::mul(
                x,
                U256::from_u64(scale_in),
            ),
            u2561e8
        );

        U256::as_u128(r)
    }

    /// Trying to find suitable `x` value.
    /// * `y0` - total reserve y (include sub `coin_out`) with transformed decimals.
    /// * `xy` - lp value (see `lp_value` func).
    /// * `x` - reserves in with transformed decimals.
    fun get_x(y0: U256, xy: U256, x: U256): U256 {
        let i = 0;
        let u2561e8 = U256::from_u128(ONE_E_8);
        let one_u256 = U256::from_u128(1);

        while (i < 255) {
            let x_prev = x;
            let k = f(x, y0);

            let cmp = U256::compare(&k, &xy);
            if (cmp == 1) {
                let dx = U256::div(
                    U256::mul(
                        U256::sub(xy, k),
                        u2561e8,
                    ),
                    dx(y0, x),
                );
                x = U256::add(x, dx);
            } else {
                let dx = U256::div(
                    U256::mul(
                        U256::sub(k, xy),
                        u2561e8,
                    ),
                    dx(y0, x),
                );
                x = U256::sub(x, dx);
            };

            cmp = U256::compare(&x, &x_prev);
            if (cmp == 2) {
                let diff = U256::sub(x, x_prev);
                cmp = U256::compare(&diff, &one_u256);
                if (cmp == 0 || cmp == 1) {
                    return x
                };
            } else {
                let diff = U256::sub(x_prev, x);
                cmp = U256::compare(&diff, &one_u256);
                if (cmp == 0 || cmp == 1) {
                    return x
                };
            };

            i = i + 1;
        };

        x
    }

    /// Trying to find suitable `y` value.
    /// * `x0` - total reserve x (include `coin_in`) with transformed decimals.
    /// * `xy` - lp value (see `lp_value` func).
    /// * `y` - reserves out with transformed decimals.
    fun get_y(x0: U256, xy: U256, y: U256): U256 {
        let i = 0;
        let u2561e8 = U256::from_u128(ONE_E_8);
        let one_u256 = U256::from_u128(1);

        while (i < 255) {
            let y_prev = y;
            let k = f(x0, y);

            let cmp = U256::compare(&k, &xy);
            if (cmp == 1) {
                let dy = U256::div(
                    U256::mul(
                        U256::sub(xy, k),
                        u2561e8,
                    ),
                    d(x0, y),
                );
                y = U256::add(y, dy);
            } else {
                let dy = U256::div(
                    U256::mul(
                        U256::sub(k, xy),
                        u2561e8,
                    ),
                    d(x0, y),
                );
                y = U256::sub(y, dy);
            };
            cmp = U256::compare(&y, &y_prev);
            if (cmp == 2) {
                let diff = U256::sub(y, y_prev);
                cmp = U256::compare(&diff, &one_u256);
                if (cmp == 0 || cmp == 1) {
                    return y
                };
            } else {
                let diff = U256::sub(y_prev, y);
                cmp = U256::compare(&diff, &one_u256);
                if (cmp == 0 || cmp == 1) {
                    return y
                };
            };

            i = i + 1;
        };

        y
    }

    /// Implements x0*y^3 + x0^3*y = x0*(y*y/1e18*y/1e18)/1e18+(x0*x0/1e18*x0/1e18)*y/1e18
    fun f(x0_u256: U256, y_u256: U256): U256 {
        let u2561e8 = U256::from_u128(ONE_E_8);

        // x0*(y*y/1e18*y/1e18)/1e18
        let yy = U256::div(
            U256::mul(y_u256, y_u256),
            u2561e8,
        );
        let yyy = U256::div(
            U256::mul(yy, y_u256),
            u2561e8,
        );
        let a = U256::div(
            U256::mul(x0_u256, yyy),
            u2561e8
        );
        //(x0*x0/1e18*x0/1e18)*y/1e18
        let xx = U256::div(
            U256::mul(x0_u256, x0_u256),
            u2561e8,
        );
        let xxx = U256::div(
            U256::mul(xx, x0_u256),
            u2561e8
        );
        let b = U256::div(
            U256::mul(xxx, y_u256),
            u2561e8,
        );

        // a + b
        U256::add(a, b)
    }

    /// Implements 3 * y0 * x^2 + y0^3 = 3 * y0 * (x * x / 1e8) / 1e8 + (y0 * y0 / 1e8 * y0) / 1e8
    fun dx(y0_u256: U256, x_u256: U256): U256 {
        let three_u256 = U256::from_u128(3);
        let u2561e8 = U256::from_u128(ONE_E_8);

        //  3 * y0 * x^2
        let y3 = U256::mul(three_u256, y0_u256);
        let xx = U256::div(
            U256::mul(x_u256, x_u256),
            u2561e8,
        );
        let yxx3 = U256::div(
            U256::mul(y3, xx),
            u2561e8,
        );
        // y0 * y0 / 1e8 * y0 / 1e8
        let yy = U256::div(
            U256::mul(y0_u256, y0_u256),
            u2561e8,
        );
        let yyy = U256::div(
            U256::mul(yy, y0_u256),
            u2561e8,
        );

        U256::add(yxx3, yyy)
    }

    /// Implements 3 * x0 * y^2 + x0^3 = 3 * x0 * (y * y / 1e8) / 1e8 + (x0 * x0 / 1e8 * x0) / 1e8
    fun d(x0_u256: U256, y_u256: U256): U256 {
        let three_u256 = U256::from_u128(3);
        let u2561e8 = U256::from_u128(ONE_E_8);

        // 3 * x0 * (y * y / 1e8) / 1e8
        let x3 = U256::mul(three_u256, x0_u256);
        let yy = U256::div(
            U256::mul(y_u256, y_u256),
            u2561e8,
        );
        let xyy3 = U256::div(
            U256::mul(x3, yy),
            u2561e8,
        );

        let xx = U256::div(
            U256::mul(x0_u256, x0_u256),
            u2561e8,
        );

        // x0 * x0 / 1e8 * x0 / 1e8
        let xxx = U256::div(
            U256::mul(xx, x0_u256),
            u2561e8,
        );

        U256::add(xyy3, xxx)
    }

    #[test]
    fun test_coin_out() {
        let out = coin_out(
            2513058000,
            1000000,
            100000000,
            25582858050757,
            2558285805075712
        );
        assert!(out == 251305799999, 0);
    }

    #[test]
    fun test_coin_out_vise_vera() {
        let out = coin_out(
            251305800000,
            100000000,
            1000000,
            2558285805075701,
            25582858050757
        );
        assert!(out == 2513057999, 0);
    }

    #[test]
    fun test_get_coin_in() {
        let in = coin_in(
            251305800000,
            100000000,
            1000000,
            2558285805075701,
            25582858050757
        );
        assert!(in == 2513058000, 0);
    }

    #[test]
    fun test_get_coin_in_vise_versa() {
        let in = coin_in(
            2513058000,
            1000000,
            100000000,
            25582858050757,
             2558285805075701
        );
        assert!(in == 251305800001, 0);
    }

    #[test]
    fun test_f() {
        let x0 = U256::from_u128(10000518365287);
        let y = U256::from_u128(2520572000001255);

        let r = U256::as_u128(f(x0, y));
        assert!(r == 160149899619106589403932994151877362, 0);

        let r = U256::as_u128(f(U256::zero(), U256::zero()));
        assert!(r == 0, 1);
    }

    #[test]
    fun test_d() {
        let x0 = U256::from_u128(10000518365287);
        let y = U256::from_u128(2520572000001255);

        let z = d(x0, y);
        let r = U256::as_u128(z);

        assert!(r == 19060937633564670887039886324, 0);

        let x0 = U256::from_u128(5000000000);
        let y = U256::from_u128(10000000000000000);

        let z = d(x0, y);
        let r = U256::as_u128(z);
        assert!(r == 150000000000012500000000000, 1);

        let x0 = U256::from_u128(1);
        let y = U256::from_u128(2);

        let z = d(x0, y);
        let r = U256::as_u128(z);
        assert!(r == 0, 2);
    }

    #[test]
    fun test_dx() {
        // 3 * y0 * x^2 + y0^3
        let x = U256::from_u128(5321542222);
        let y0 = U256::from_u128(108590000002874000);

        let r = dx(y0, x);
        assert!(128047026988067802242015266600149752 == U256::as_u128(r), 0);

        let x = U256::from_u128(10240000);
        let y0 = U256::from_u128(25600000);
        let r = dx(y0, x);
        assert!(2483027 == U256::as_u128(r), 1);
    }

    #[test]
    fun test_lp_value_compute() {
        // 0.3 ^ 3 * 0.5 + 0.5 ^ 3 * 0.3 = 0.051 (12 decimals)
        let lp_value = lp_value(300000, 1000000, 500000, 1000000);
        assert!(
            U256::as_u128(lp_value) == 5100000,
            0
        );

        lp_value = lp_value(
            500000899318256,
            1000000,
            25000567572582123,
            1000000000000
        );

        assert!(U256::as_u128(lp_value) == 312508781701599715772530613362069248234, 1);
    }
}
