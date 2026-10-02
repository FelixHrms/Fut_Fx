*------------------------------------------------------------------------------
* 03_plots.do
* Plots based on lab_prj_emir_ecb.hermesf_fut, read via ODBC.
*------------------------------------------------------------------------------

	global path "C:\Users\hermesf\Projects\Future_FX_cleaning"
	global dsn  "Hermes_DSN"

*------------------------------------------------------------------------------
* 1. Net positions by country: EA and non EA hedge funds, non euro area dealers,
*    MFIs and OFIs. One chart per country (DE, IT, US).
*------------------------------------------------------------------------------

	foreach c in DE IT US {

		if "`c'" == "US" local ccy "USD"
		else             local ccy "EUR"
		if "`c'" == "DE" local name "German sovereign bond futures"
		if "`c'" == "IT" local name "Italian sovereign bond futures"
		if "`c'" == "US" local name "US Treasury futures"

	* net by day, sector and counterparty country
		#delimit ;
		odbc load, clear lowercase dsn("${dsn}") exec("
			SELECT reference_period, sector, country, SUM(net) AS net
			FROM (
				SELECT reference_period, buyer_sector AS sector, buyer_country AS country, notional AS net
				FROM lab_prj_emir_ecb.hermesf_fut
				WHERE product_country = '`c''
				UNION ALL
				SELECT reference_period, seller_sector AS sector, seller_country AS country, -notional AS net
				FROM lab_prj_emir_ecb.hermesf_fut
				WHERE product_country = '`c''
			) x
			WHERE sector IN ('HF', 'DEALER', 'MFI', 'OFI')
			GROUP BY reference_period, sector, country
		") ;
		#delimit cr

		gen date = date(reference_period, "YMD")
		format date %td
		replace net = net / 1e9                                   // bn

	* euro area flag (Croatia from 2023, Bulgaria from 2026)
		gen isea = inlist(country, "AT", "BE", "CY", "EE", "FI", "FR", "DE", "GR", "IE") ///
				 | inlist(country, "IT", "LV", "LT", "LU", "MT", "NL", "PT", "SK", "SI") ///
				 | country == "ES" ///
				 | (country == "HR" & date >= td(01jan2023)) ///
				 | (country == "BG" & date >= td(01jan2026))

	* groups to plot
		gen group = ""
		replace group = "hf_ea"        if sector == "HF"     &  isea
		replace group = "hf_nonea"     if sector == "HF"     & !isea
		replace group = "dealer_nonea" if sector == "DEALER" & !isea
		replace group = "mfi_nonea"    if sector == "MFI"    & !isea
		replace group = "ofi_nonea"    if sector == "OFI"    & !isea
		drop if group == ""

		collapse (sum) net, by(date group)
		reshape wide net, i(date) j(group) string
		foreach g in hf_ea hf_nonea dealer_nonea mfi_nonea ofi_nonea {
			capture confirm variable net`g'
			if _rc gen net`g' = .
		}

	* a few empty days inside the excluded REFIT transition window, so the lines break there
	* and the break shows as a small gap on the index axis
		local gap_days = 35
		local n0 = _N
		set obs `=_N + `gap_days''
		replace date = td(01jul2024) + _n - `n0' if _n > `n0'
		sort date

	* combined line of the five groups
		egen nettotal = rowtotal(nethf_ea nethf_nonea netdealer_nonea netmfi_nonea netofi_nonea), missing

	* x axis as a running day index, so the excluded window collapses to a small gap
		gen t = _n
		gen yr = year(date)
		bys yr (date): gen first = _n == 1
		local xlab ""
		forvalues i = 1/`=_N' {
			if first[`i'] local xlab `"`xlab' `i' "`=yr[`i']'""'
		}
		summ t if date < td(29apr2024), meanonly
		local gap_start = r(max)
		summ t if date >= td(01jan2025), meanonly
		local gap_end = r(min)

	* plot, dashed vertical lines mark the excluded REFIT transition window
		twoway (line nethf_ea        t, cmissing(n)) ///
			   (line nethf_nonea     t, cmissing(n)) ///
			   (line netdealer_nonea t, cmissing(n)) ///
			   (line netmfi_nonea    t, cmissing(n)) ///
			   (line netofi_nonea    t, cmissing(n)) ///
			   (line nettotal        t, cmissing(n) lcolor(black) lwidth(medthick)), ///
			legend(order(1 "EA hedge funds" 2 "Non-EA hedge funds" 3 "Non-EA dealers" 4 "Non-EA MFIs" 5 "Non-EA OFIs" 6 "Combined") rows(2) position(6)) ///
			ytitle("Net position, `ccy' bn") xtitle("") yline(0, lcolor(gs10)) ///
			xlabel(`xlab') xline(`gap_start' `gap_end', lpattern(dash) lcolor(gs8)) ///
			title("Net positions in `name'")
		graph export "${path}\net_positions_`=lower("`c'")'.png", replace width(1600)
	}
