*------------------------------------------------------------------------------
* 03_plots.do
* Plots based on lab_prj_emir_ecb.hermesf_fut, read via ODBC.
*------------------------------------------------------------------------------

	global path "C:\Users\hermesf\Projects\Future_FX_cleaning"
	global dsn  "Hermes_DSN"

*------------------------------------------------------------------------------
* 1. Net positions in German futures: hedge funds, non euro area dealers, MFIs, OFIs
*------------------------------------------------------------------------------

* net by day, sector and counterparty country, German contracts only
	#delimit ;
	odbc load, clear lowercase dsn("${dsn}") exec("
		SELECT reference_period, sector, country, SUM(net) AS net
		FROM (
			SELECT reference_period, buyer_sector AS sector, buyer_country AS country, notional AS net
			FROM lab_prj_emir_ecb.hermesf_fut
			WHERE product_country = 'DE'
			UNION ALL
			SELECT reference_period, seller_sector AS sector, seller_country AS country, -notional AS net
			FROM lab_prj_emir_ecb.hermesf_fut
			WHERE product_country = 'DE'
		) x
		WHERE sector IN ('HF', 'DEALER', 'MFI', 'OFI')
		GROUP BY reference_period, sector, country
	") ;
	#delimit cr

	gen date = date(reference_period, "YMD")
	format date %td
	replace net = net / 1e9                                   // EUR bn

* euro area flag (Croatia from 2023, Bulgaria from 2026)
	gen isea = inlist(country, "AT", "BE", "CY", "EE", "FI", "FR", "DE", "GR", "IE") ///
			 | inlist(country, "IT", "LV", "LT", "LU", "MT", "NL", "PT", "SK", "SI") ///
			 | country == "ES" ///
			 | (country == "HR" & date >= td(01jan2023)) ///
			 | (country == "BG" & date >= td(01jan2026))

* groups to plot
	gen group = ""
	replace group = "hf"           if sector == "HF"
	replace group = "dealer_nonea" if sector == "DEALER" & !isea
	replace group = "mfi_nonea"    if sector == "MFI"    & !isea
	replace group = "ofi_nonea"    if sector == "OFI"    & !isea
	drop if group == ""

	collapse (sum) net, by(date group)
	reshape wide net, i(date) j(group) string

* one empty day inside the excluded REFIT transition window, so the lines break there
	set obs `=_N + 1'
	replace date = td(01jul2024) in L
	sort date

* plot
	twoway (line nethf           date, cmissing(n)) ///
		   (line netdealer_nonea date, cmissing(n)) ///
		   (line netmfi_nonea    date, cmissing(n)) ///
		   (line netofi_nonea    date, cmissing(n)), ///
		legend(order(1 "Hedge funds" 2 "Non-EA dealers" 3 "Non-EA MFIs" 4 "Non-EA OFIs") rows(1) position(6)) ///
		ytitle("Net position, EUR bn") xtitle("") yline(0, lcolor(gs10)) ///
		title("Net positions in German sovereign bond futures")
	graph export "${path}\net_positions_de.png", replace width(1600)
