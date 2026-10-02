*------------------------------------------------------------------------------
* 03_plots.do
* Plots based on lab_prj_emir_ecb.hermesf_fut, read via ODBC.
*------------------------------------------------------------------------------

	global path "C:\Users\hermesf\Projects\Future_FX_cleaning"
	global dsn  "Hermes_DSN"

*------------------------------------------------------------------------------
* Program: net position chart for one country and a list of sector groups
*   groups: hf_ea hf_nonea dealer_nonea mfi_nonea ofi_nonea ucits icpf
*   total:  groups summed into the combined line (default: all plotted groups)
*   total2: groups summed into a second combined line (optional)
*   usage:  plot_net DE, groups(hf_ea hf_nonea ucits) total(hf_ea hf_nonea) total2(ucits) suffix(_x)
*------------------------------------------------------------------------------

	capture program drop plot_net
	program define plot_net
		syntax anything(name=c), groups(string) [total(string) total2(string) suffix(string)]
		if "`total'" == "" local total "`groups'"

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
			WHERE sector IN ('HF', 'DEALER', 'MFI', 'OFI', 'UCITS', 'ICPF')
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

	* sector groups
		gen group = ""
		replace group = "hf_ea"        if sector == "HF"     &  isea
		replace group = "hf_nonea"     if sector == "HF"     & !isea
		replace group = "dealer_nonea" if sector == "DEALER" & !isea
		replace group = "mfi_nonea"    if sector == "MFI"    & !isea
		replace group = "ofi_nonea"    if sector == "OFI"    & !isea
		replace group = "ucits"        if sector == "UCITS"
		replace group = "icpf"         if sector == "ICPF"
		drop if group == ""

		collapse (sum) net, by(date group)
		reshape wide net, i(date) j(group) string
		foreach g in `groups' {
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

	* combined line
		local vars ""
		foreach g in `total' {
			local vars "`vars' net`g'"
		}
		egen nettotal = rowtotal(`vars'), missing
		if "`total2'" != "" {
			local vars ""
			foreach g in `total2' {
				local vars "`vars' net`g'"
			}
			egen nettotal2 = rowtotal(`vars'), missing
		}

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
		local label_hf_ea        "EA hedge funds"
		local label_hf_nonea     "Non-EA hedge funds"
		local label_dealer_nonea "Non-EA dealers"
		local label_mfi_nonea    "Non-EA MFIs"
		local label_ofi_nonea    "Non-EA OFIs"
		local label_ucits        "UCITS"
		local label_icpf         "Insurers and pension funds"
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
		else                       local label_total "Combined excl. UCITS and ICPF"
		local legend `"`legend' `k' "`label_total'""'
		local lines2 ""
		if "`total2'" != "" {
			local ++k
			local lines2 `"(line nettotal2 t, cmissing(n) lcolor(black) lwidth(medthick) lpattern(dash))"'
			local legend `"`legend' `k' "Combined UCITS and ICPF""'
		}
		twoway `lines' (line nettotal t, cmissing(n) lcolor(black) lwidth(medthick)) `lines2', ///
			legend(order(`legend') rows(3) position(6)) ///
			ytitle("Net position, `ccy' bn") xtitle("") yline(0, lcolor(gs10)) ///
			xlabel(`xlab') xline(`gap_start' `gap_end', lpattern(dash) lcolor(gs8)) ///
			title("Net positions in `name'")
		graph export "${path}\net_positions_`=lower("`c'")'`suffix'.png", replace width(1600)
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
* 3. Same, plus UCITS and insurers and pension funds, with a second combined line
*------------------------------------------------------------------------------

	foreach c in DE IT US {
		plot_net `c', groups(hf_ea hf_nonea dealer_nonea mfi_nonea ofi_nonea ucits icpf) ///
					  total(hf_ea hf_nonea dealer_nonea mfi_nonea ofi_nonea) ///
					  total2(ucits icpf) suffix("_ucits_icpf")
	}
