*------------------------------------------------------------------------------
* 03_plots.do
* Plots based on lab_prj_emir_ecb.hermesf_fut, read via ODBC.
*------------------------------------------------------------------------------

	global path "C:\Users\hermesf\Projects\Future_FX_cleaning"
	global dsn  "Hermes_DSN"

*------------------------------------------------------------------------------
* Helper programs
*------------------------------------------------------------------------------

* load net positions by day, sector and counterparty country for one product country
	capture program drop load_net
	program define load_net
		args c
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
	end

* after collapsing to one row per date: insert a small gap for the excluded REFIT
* transition window and build a running day index with year labels
	capture program drop gap_axis
	program define gap_axis, rclass
		local gap_days = 35
		local n0 = _N
		set obs `=_N + `gap_days''
		replace date = td(01jul2024) + _n - `n0' if _n > `n0'
		sort date
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
		return local xlab `"`xlab'"'
		return local xline "`gap_start' `gap_end'"
	end

* chart options shared by all charts
	capture program drop chart_name
	program define chart_name, rclass
		args c
		if "`c'" == "US" return local ccy "USD"
		else             return local ccy "EUR"
		if "`c'" == "DE" return local name "German sovereign bond futures"
		if "`c'" == "IT" return local name "Italian sovereign bond futures"
		if "`c'" == "US" return local name "US Treasury futures"
	end

*------------------------------------------------------------------------------
* Program: net position chart by sector group
*   groups: hf_ea hf_nonea dealer_nonea mfi_nonea ofi_nonea ucits
*   total:  groups summed into the combined line (default: all plotted groups)
*   usage:  plot_net DE, groups(hf_ea hf_nonea ucits) total(hf_ea hf_nonea) suffix(_x)
*------------------------------------------------------------------------------

	capture program drop plot_net
	program define plot_net
		syntax anything(name=c), groups(string) [total(string) suffix(string)]
		if "`total'" == "" local total "`groups'"
		chart_name `c'
		local ccy  "`r(ccy)'"
		local name "`r(name)'"

		load_net `c'
		gen group = ""
		replace group = "hf_ea"        if sector == "HF"     &  isea
		replace group = "hf_nonea"     if sector == "HF"     & !isea
		replace group = "dealer_nonea" if sector == "DEALER" & !isea
		replace group = "mfi_nonea"    if sector == "MFI"    & !isea
		replace group = "ofi_nonea"    if sector == "OFI"    & !isea
		replace group = "ucits"        if sector == "UCITS"
		drop if group == ""

		collapse (sum) net, by(date group)
		reshape wide net, i(date) j(group) string
		foreach g in `groups' {
			capture confirm variable net`g'
			if _rc gen net`g' = .
		}
		gap_axis
		local xlab  `"`r(xlab)'"'
		local xline "`r(xline)'"

		local vars ""
		foreach g in `total' {
			local vars "`vars' net`g'"
		}
		egen nettotal = rowtotal(`vars'), missing

		local label_hf_ea        "EA hedge funds"
		local label_hf_nonea     "Non-EA hedge funds"
		local label_dealer_nonea "Non-EA dealers"
		local label_mfi_nonea    "Non-EA MFIs"
		local label_ofi_nonea    "Non-EA OFIs"
		local label_ucits        "UCITS"
		local lines ""
		local legend ""
		local k = 0
		foreach g in `groups' {
			local ++k
			local lines  `"`lines' (line net`g' t, cmissing(n))"'
			local legend `"`legend' `k' "`label_`g''""'
		}
		local ++k
		if "`total'" == "`groups'" local label_total "Combined"
		else                       local label_total "Combined excl. UCITS"
		twoway `lines' (line nettotal t, cmissing(n) lcolor(black) lwidth(medthick)), ///
			legend(order(`legend' `k' "`label_total'") rows(2) position(6)) ///
			ytitle("Net position, `ccy' bn") xtitle("") yline(0, lcolor(gs10)) ///
			xlabel(`xlab') xline(`xline', lpattern(dash) lcolor(gs8)) ///
			title("Net positions in `name'")
		graph export "${path}\net_positions_`=lower("`c'")'`suffix'.png", replace width(1600)
	end

*------------------------------------------------------------------------------
* Program: three block chart
*   real money (UCITS, insurers and pension funds), leveraged and foreign
*   (hedge funds, non EA dealers, MFIs and OFIs), and the residual of all other sectors
*------------------------------------------------------------------------------

	capture program drop plot_blocks
	program define plot_blocks
		args c
		chart_name `c'
		local ccy  "`r(ccy)'"
		local name "`r(name)'"

		load_net `c'
		gen block = "other"
		replace block = "realmoney" if inlist(sector, "UCITS", "ICPF")
		replace block = "levfor"    if sector == "HF" | (inlist(sector, "DEALER", "MFI", "OFI") & !isea)

		collapse (sum) net, by(date block)
		reshape wide net, i(date) j(block) string
		gap_axis
		local xlab  `"`r(xlab)'"'
		local xline "`r(xline)'"

		twoway (line netrealmoney t, cmissing(n)) ///
			   (line netlevfor    t, cmissing(n)) ///
			   (line netother     t, cmissing(n) lcolor(gs8)), ///
			legend(order(1 "UCITS, insurers and pension funds" ///
						 2 "Hedge funds and non-EA dealers, MFIs, OFIs" ///
						 3 "All other sectors") rows(3) position(6)) ///
			ytitle("Net position, `ccy' bn") xtitle("") yline(0, lcolor(gs10)) ///
			xlabel(`xlab') xline(`xline', lpattern(dash) lcolor(gs8)) ///
			title("Net positions in `name'")
		graph export "${path}\net_positions_`=lower("`c'")'_blocks.png", replace width(1600)
	end

*------------------------------------------------------------------------------
* 1. Hedge funds (EA, non EA), non EA dealers, MFIs and OFIs
*------------------------------------------------------------------------------

	foreach c in DE IT US {
		plot_net `c', groups(hf_ea hf_nonea dealer_nonea mfi_nonea ofi_nonea)
	}

*------------------------------------------------------------------------------
* 2. Same, plus UCITS
*------------------------------------------------------------------------------

	foreach c in DE IT US {
		plot_net `c', groups(hf_ea hf_nonea dealer_nonea mfi_nonea ofi_nonea ucits) ///
					  total(hf_ea hf_nonea dealer_nonea mfi_nonea ofi_nonea) suffix("_ucits")
	}

*------------------------------------------------------------------------------
* 3. Three blocks: real money, leveraged and foreign, all others
*------------------------------------------------------------------------------

	foreach c in DE IT US {
		plot_blocks `c'
	}
