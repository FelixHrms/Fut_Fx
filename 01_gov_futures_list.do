*------------------------------------------------------------------------------
* 01_gov_futures_list.do
* Build a list of euro area sovereign bond futures (ISIN, country, expiry)
* from the Eurex contracts sheet. Interest rate futures (FEU3, FST3) dropped.
* Output: gov_fut.csv
*------------------------------------------------------------------------------

	global path "C:\Users\hermesf\Projects\Future_FX_cleaning"

	import excel "${path}\eurex_sovereign_futures_contracts.xlsx", ///
		sheet("Contracts") firstrow clear

	keep Product ISIN ExpirationDate
	duplicates drop

	* keep only sovereign bond futures
	keep if inlist(Product, "FGBS", "FGBM", "FGBL", "FGBX") ///
		  | inlist(Product, "FBTS", "FBTM", "FBTP") ///
		  | inlist(Product, "FOAM", "FOAT", "FBON")

	* country of the underlying sovereign
	gen country = ""
	replace country = "DE" if inlist(Product, "FGBS", "FGBM", "FGBL", "FGBX")
	replace country = "IT" if inlist(Product, "FBTS", "FBTM", "FBTP")
	replace country = "FR" if inlist(Product, "FOAM", "FOAT")
	replace country = "ES" if inlist(Product, "FBON")
	assert country != ""

	* expiration date as a Stata date
	gen expiration_date = dofc(ExpirationDate)
	format expiration_date %tdCCYY-NN-DD

	rename ISIN isin
	keep isin country expiration_date
	order isin country expiration_date
	sort country expiration_date isin

	isid isin

	export delimited using "${path}\gov_fut.csv", replace datafmt
