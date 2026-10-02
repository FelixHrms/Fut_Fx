
	global data "P:\ECB business areas\DGM\SM_Team\SM_Team_Consultants\Andrea Poinelli\EA US basis\A Data"
	
	
*------------------------------------------------------------------------------
* 0.  Create excel files for EURIBOR/ESTR FUTURES and GOVTFUTURES
*------------------------------------------------------------------------------
 
	import excel "${data}\EMIR\ESMA query\eurex_sovereign_futures_contracts.xlsx", sheet("Contracts") firstrow clear
	keep Product ISIN
	duplicates drop
	gen tag_SOVFUT = 1 if inlist(Product,"FGBL","FBTP","FBTM","FBTS","FBON") | inlist(Product,"FGBM","FGBX","FOAT","FGBS","FOAM")
	gen tag_OTHERFUT = 1 if inlist(Product,"FEU3","FST3")
	preserve
		rename _all, lower
		rename isin product_id
		gen product_country = "IT" if inlist(product,"FBTM","FBTP","FBTS")
		replace product_country = "ES" if inlist(product,"FBON")
		replace product_country = "FR" if inlist(product,"FOAM","FOAT")
		replace product_country = "DE" if inlist(product,"FGBL","FGBM","FGBS","FGBX")
		replace product_country = "EU" if inlist(product,"FEU3","FST3")
		save "${data}\EMIR\ESMA query\fut_class.dta", replace
	restore
	preserve 
		keep ISIN tag_SOVFUT
		rename ISIN isin
		keep if tag_SOVFUT == 1
		drop tag_SOVFUT
		export delimited using "${data}\EMIR\ESMA query\gov_fut.csv", replace
	restore
	preserve 
		keep ISIN tag_OTHERFUT
		rename ISIN isin
		keep if tag_OTHERFUT == 1
		drop tag_OTHERFUT
		export delimited using "${data}\EMIR\ESMA query\other_fut.csv", replace
	restore	

*------------------------------------------------------------------------------
* 1.  Create List of Eurex clearing members
*------------------------------------------------------------------------------
	
	import delimited "${data}\EMIR\Eurex clearing members\memberdb.csv", varnames(1) clear
	duplicates drop
	gen _isEurexCM = 1
	save "${data}\EMIR\Eurex clearing members\members.dta", replace

*------------------------------------------------------------------------------
* 2.  Helper: turn a string variable's distinct values into a single-quoted,
*     comma-separated SQL IN-list, returned in r(list).
*------------------------------------------------------------------------------
	
	capture program drop build_inlist
	program define build_inlist, rclass
		syntax varname(string)
		local out ""
		forvalues i = 1/`=_N' {
			local v = `varlist'[`i']
			if `"`v'"' != "" {
				if `"`out'"' == "" {
					local out `"'`v''"'
				}
				else {
					local out `"`out','`v''"'
				}
			}
		}
		return local list `"`out'"'
	end
	
*------------------------------------------------------------------------------
* 3.  Whitelists -> macros
*------------------------------------------------------------------------------

	* 1a. Govt Futures ISINs    
	import delimited "${data}\EMIR\ESMA query\gov_fut.csv", clear varnames(1) stringcols(_all)
	capture confirm variable isin
	if _rc {
		quietly ds
		local vars `r(varlist)'
		local n : word count `vars'
		local lastvar : word `n' of `vars'
		rename `lastvar' isin
		di as txt "Note: using -`lastvar'- as the ISIN column (rename to isin to override)."
	}
	drop if missing(isin)
	keep isin
	duplicates drop
	build_inlist isin
	local gov_futures `"`r(list)'"'
	di `"`gov_futures'"'

	* 1b. OTHER Futures ISINs   
	import delimited "${data}\EMIR\ESMA query\other_fut.csv", clear varnames(1) stringcols(_all)
	capture confirm variable isin
	if _rc {
		quietly ds
		local vars `r(varlist)'
		local n : word count `vars'
		local lastvar : word `n' of `vars'
		rename `lastvar' isin
		di as txt "Note: using -`lastvar'- as the ISIN column (rename to isin to override)."
	}
	drop if missing(isin)
	keep isin
	duplicates drop
	build_inlist isin
	local other_futures `"`r(list)'"'
	di `"`other_futures'"'
	
	di as txt "Government ISIN  list length (chars): " strlen(`"`gov_futures'"')
	di as txt "Other ISIN  list length (chars): " strlen(`"`other_futures'"')
	di as txt "HF-id list length (chars): " strlen(`"`hfunds'"')
	di as txt "Stata macro limit         : " c(macrolen)

*------------------------------------------------------------------------------
* 4.  Pull data 
*------------------------------------------------------------------------------
	/* notes:
		- Need to introduce e.leg1_price_rate AS price, in both
		- trial isin for refit DE000F1NGF53, trial isin for prerefit DE000C1J3KW7
	*/ 
	
	*** QUERY PRE-REFIT [12dec2017,26apr2024] ***
	
	#delimit ;
	odbc load, clear lowercase dsn("DEVO Impala 64bit")
	exec("
		SELECT e.tec_ruti,
			   e.reference_period                   		AS business_date,
			   e.leg1_counterparty_side             		AS direction,
			   e.leg1_notional                      		AS vol,
			   e.leg1_reporting_cpty_id              		AS reporter,
			   s_rep.sector                          		AS reporter_sector,
			   e.leg1_reporting_cpty_id_country_code 		AS reporter_country,
			   e.leg1_other_cpty_id                  		AS otherparty,
			   s_oth.sector                          		AS otherparty_sector,
			   e.leg1_other_cpty_id_country_code     		AS otherparty_country,
			   e.leg1_product_id                     		AS product_id,
			   e.leg1_ccp_id                         		AS ccp,
			   e.leg1_maturity_date                  		AS maturity
		FROM crp_emir_ecb.emir_ecb_states_deduplicated e
		LEFT JOIN xlab_ecb_prj_sftds_cb_common.pth_sector s_rep
			   ON e.leg1_reporting_cpty_id = s_rep.lei
		LEFT JOIN xlab_ecb_prj_sftds_cb_common.pth_sector s_oth
			   ON e.leg1_other_cpty_id = s_oth.lei
		WHERE e.leg1_reporting_cpty_id_type = 'LEI' AND e.leg1_other_cpty_id_type = 'LEI'
		  AND e.leg1_product_id IN (`gov_futures')
		  AND e.leg1_asset_class = 'INTR' AND e.leg1_contract_type = 'FUTR'
		  AND e.leg1_notional > 0 AND e.leg1_notional <= 1e11
		  AND e.leg1_notional_currency1 IN ('EUR')
		  AND LEFT(e.leg1_product_clssfctn, 2) = 'FF'
		  AND LEFT(e.leg1_product_clssfctn, 3) NOT IN ('FFC','FFS')
	") ;
	#delimit cr
	save "${data}\EMIR\raw\fut_emir_prerefit.dta", replace
	
	
	*** QUERY REFIT [29apr2024,16sep2026] ***

	#delimit ;
	odbc load, clear lowercase dsn("DEVO Impala 64bit")
	exec("
		SELECT e.tec_ruti,
			   e.reference_period                            AS business_date,
			   e.leg1_direction                              AS direction,
			   e.leg1_notional_leg1                          AS vol,
			   e.leg1_reporting_cpty_id                      AS reporter,
			   s_rep.sector                                  AS reporter_sector,
			   e.leg1_reporting_cpty_id_country_code_gleif   AS reporter_country,
			   e.leg1_other_cpty_id                          AS otherparty,
			   s_oth.sector                                  AS otherparty_sector,
			   e.leg1_other_cpty_id_country_code_gleif       AS otherparty_country,
			   e.leg1_product_isin                           AS product_id,
			   e.leg1_ccp_id                                 AS ccp,
			   e.leg1_maturity_date                          AS maturity
		FROM crp_emir_refit_ecb.emir_refit_ecb_trade_states_deduplicated e
		LEFT JOIN xlab_ecb_prj_sftds_cb_common.pth_sector s_rep
			   ON e.leg1_reporting_cpty_id = s_rep.lei
		LEFT JOIN xlab_ecb_prj_sftds_cb_common.pth_sector s_oth
			   ON e.leg1_other_cpty_id = s_oth.lei
		WHERE e.leg1_reporting_cpty_id_type = 'LEI' AND e.leg1_other_cpty_id_type = 'LEI'
		  AND e.leg1_product_isin IN (`gov_futures')
		  AND e.leg1_asset_class = 'INTR' AND e.leg1_contract_type = 'FUTR'
		  AND e.leg1_notional_leg1 > 0 AND e.leg1_notional_leg1 <= 1e11
		  AND e.leg1_notional_leg1_currency IN ('EUR')
		  AND LEFT(e.leg1_product_cfi, 2) = 'FF'
		  AND LEFT(e.leg1_product_cfi, 3) NOT IN ('FFC','FFS')
	") ;
	#delimit cr
	save "${data}\EMIR\raw\fut_emir_refit.dta", replace
	
*------------------------------------------------------------------------------
* 5. Data cleaning 
*------------------------------------------------------------------------------	
	
	local dataset refit // prerefit
	foreach d of local dataset {
		
		use "${data}\EMIR\raw\fut_emir_`d'.dta", clear
		
		** date variable & units
			gen date = date(business_date,"YMD")
				format date %td
			replace vol = vol / 1000000000 // in EUR bn
			gen maturity_date = dofc(maturity)	
			bys product_id: egen product_maturity = mode(maturity_date)
				format product_maturity %td
		** adjust direction	(in refit only)
			drop if !inlist(direction,"BYER","SLLR")
		** EA vs non-EA flag. Remember that prior to Brexit implementation, GB was considered EU, therefore we see counterparties from GB being reporters.
			gen reporter_isea = "NONEA"
				replace reporter_isea = "EA" if inlist(reporter_country, "AT", "BE", "CY", "EE", "FI", "FR", "DE", "GR", "IE") ///
											  | inlist(reporter_country, "IT", "LV", "LT", "LU", "MT", "NL", "PT", "SK", "SI") ///
											  | inlist(reporter_country, "ES", "E$")
				replace reporter_isea = "EA" if reporter_country == "HR" & date >= td(01jan2023)
				replace reporter_isea = "EA" if reporter_country == "BG" & date >= td(01jan2026)

			gen otherparty_isea = "NONEA"
				replace otherparty_isea = "EA" if inlist(otherparty_country, "AT", "BE", "CY", "EE", "FI", "FR", "DE", "GR", "IE") ///
												| inlist(otherparty_country, "IT", "LV", "LT", "LU", "MT", "NL", "PT", "SK", "SI") ///
												| inlist(otherparty_country, "ES", "E$")
				replace otherparty_isea = "EA" if otherparty_country == "HR" & date >= td(01jan2023)
				replace otherparty_isea = "EA" if otherparty_country == "BG" & date >= td(01jan2026)
		** some LEI have no sector 
			replace reporter_sector = "NA" if reporter_sector == ""
			replace otherparty_sector = "NA" if otherparty_sector == ""
		** flag for Eurex clearing member. CCP are NOT CONSIDERED CLEARING MEMEBER
			rename reporter lei 
			merge m:1 lei using "${data}\EMIR\Eurex clearing members\members.dta", keep(3 1) nogen
			rename (lei _isEurexCM) (reporter reporter_isEurexCM) 
			rename otherparty lei 
			merge m:1 lei using "${data}\EMIR\Eurex clearing members\members.dta", keep(3 1) nogen
			rename (lei _isEurexCM) (otherparty otherparty_isEurexCM) 		
		** ccp flag and create new sector: see https://www.esma.europa.eu/sites/default/files/library/third-country_ccps_recognised_under_emir.pdf
			local ccp_leis ///
			529900LN3S50JPU47S06 529900G3SW56SHYNPR95 549300JQL1BXTGCCGP11 213800NM8ZN1F16ARD34 ///
			213800WPJUJBAVXI5162 213800CKBBZUAHHARH83 213800NAOHHKRD9IHE35 549300JHM7D8P3TS4S86 ///
			353800016BHKLPQSXY33 549300CMH3J8ASUM8N29 549300ZLWT3FK3F0FW61 549300FKHU9M1PAGIO86 ///
			213800PJDCEXAVMM3J32 549300MDWJV6LDHP3U32 549300MZWLT9C8T4VI12 5493004XJK1P32XQLA57 ///
			549300T5G56HZH1I6F15 5493000C6JWJSISPU377 549300TJ3RRV6Q1UEW14 SNZ2OJLFK8MNNCLQOF39 ///
			T33OE4AS4QXXS2TT7X50 549300RGCVWZUN04IA69 549300HWWR1D8OTS2G29 549300958ME22EPI3U08 ///
			335800CNVQFGRCP1PR55 213800QL3V1PYPQMLU38 353800014689ADHKNO82 4GTK5S46E6H318LMDS44 ///
			549300P2ZLEW2OKT5733 335800EV4FPEFRWNVX08 2138003214435KV3SI18 335800QRNLKAHGA1BL68 ///
			54930002A8LR1AAUCU78 724500937F740MHCX307 2594000K576D5CQXI987 8156006407E264D2C725 ///
			R1IO4YJ0O79SMWVCHB58 529900M6JY6PUZ9NTA71 F226TOH6YD6XJB17KS62 529900MHIW6Z8OTOAH28 ///
			6SI7IOVECKBHVYBTB459 529900QF6QY66QULSI15 213800L8AQD59D3JRW81 5299009QA8BBE2OOB349 ///
			5299001PSXO7X2JX4W10 7245003TLNC4R9XFDX32 213800IW53U9JMJ4QR40 5R6J7JCQRIPQR1EEP713 ///
			549300ZD7BBOVZFVHK49
			gen byte reporter_isccp   = 0
			gen byte otherparty_isccp = 0
			foreach lei of local ccp_leis {
				quietly replace reporter_isccp       = 1 if reporter   == "`lei'"
				quietly replace otherparty_isccp     = 1 if otherparty == "`lei'"		
			}
			replace reporter_sector = "CCP" if reporter_isccp == 1
			replace otherparty_sector = "CCP" if otherparty_isccp == 1
		** categorize trades
			gen trade_type = ""
				replace trade_type = "CLIENT_CLIENT" if otherparty_isEurexCM == . & reporter_isEurexCM == .
				replace trade_type = "MEMBER_MEMBER" if otherparty_isEurexCM == 1 & reporter_isEurexCM == 1
				replace trade_type = "CLIENT_MEMBER" if (otherparty_isEurexCM == 1 & reporter_isEurexCM == .) | (otherparty_isEurexCM == . & reporter_isEurexCM == 1)			
				replace trade_type = "CLIENT_CCP" if trade_type == "CLIENT_CLIENT" & (otherparty_isccp == 1 | reporter_isccp == 1)
				replace trade_type = "MEMBER_CCP" if trade_type == "MEMBER_MEMBER" & (otherparty_isccp == 1 | reporter_isccp == 1)
				replace trade_type = "CCP_CCP" if  otherparty_isccp == 1 & reporter_isccp == 1
		** drop unused variables and order 
			order date
			drop business_date maturity_date maturity
		** merge type of future from ESMA query
			merge m:1 product_id using "${data}\EMIR\ESMA query\fut_class.dta", keep(1 3) nogen
		
	*** CHECKS ***
	/* 
		** who are the biggest players by sector?
			preserve 
				gen sector =  reporter_sector + "_" + reporter_isea
				collapse (sum) vol, by(reporter sector)
				bysort sector (vol): gen rank = _N - _n + 1
				by sector: keep if rank <= 10
				sort sector rank
			restore 	
	*/
	
	*** ALLOCATE BUYERS AND SELLERS ***
	
		foreach rep of varlist reporter reporter_sector reporter_country reporter_isea reporter_isccp reporter_isEurexCM {
			local oth  : subinstr local rep "reporter" "otherparty"
			local buy  : subinstr local rep "reporter" "futbuyer"
			local sell : subinstr local rep "reporter" "futseller"

			clonevar `buy'  = `rep' if direction == "BYER"
			replace  `buy'  = `oth' if direction == "SLLR"
			clonevar `sell' = `rep' if direction == "SLLR"
			replace  `sell' = `oth' if direction == "BYER"
		}
		drop direction reporter* otherparty*
	
	*** SAVE ***
		
		save "${data}\EMIR\clean\fut_emir_`d'.dta", replace
	
	}
	
		
*------------------------------------------------------------------------------
* 5.  Graph
*------------------------------------------------------------------------------
		
	*** NET POSITIONS BY SECTOR ***
	
		** save by position
			local dataset refit // prerefit
			foreach d of local dataset { 
				use "${data}\EMIR\clean\fut_emir_`d'.dta", clear
				preserve
					collapse (sum) vol_long = vol, by(date futbuyer_sector futbuyer_isea product_country)
					rename (futbuyer_sector futbuyer_isea) (sector ea)
					save "${data}\EMIR\temp\fut_emir_`d'_long.dta", replace
				restore 
				preserve
					collapse (sum) vol_short = vol, by(date futseller_sector futseller_isea product_country)
					rename (futseller_sector futseller_isea) (sector ea)		
					save "${data}\EMIR\temp\fut_emir_`d'_short.dta", replace
				restore 	
				use "${data}\EMIR\temp\fut_emir_`d'_long.dta", clear
				merge 1:1 date sector ea product_country using "${data}\EMIR\temp\fut_emir_`d'_short.dta", nogen
				save "${data}\EMIR\temp\fut_emir_`d'_longshort.dta", replace
			} 
	
		** upload positions and clean
			use "${data}\EMIR\temp\fut_emir_refit_longshort.dta", clear
			append using "${data}\EMIR\temp\fut_emir_prerefit_longshort.dta"
			replace vol_long = 0 if vol_long == .
			replace vol_short = 0 if vol_short == .
			gen sec = sector + "_" + ea
			gen vol_net = vol_long - vol_short 
		
		** graph 
			keep if product_country == "FR"
			keep vol_net date sec
			reshape wide vol_net, i(date) j(sec) string
			rename vol_net* vol_net_*
			
			* all sectors
			graph bar vol_net_HF_NONEA vol_net_DEALER_NONEA vol_net_OFI_NONEA vol_net_ICPF_EA if !inrange(date,td(01jan2024),td(01dec2024)) & date > td(01jan2018), over(date) stack legend(position(6) row(3) size(small))
			
			
