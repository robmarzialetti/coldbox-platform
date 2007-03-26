<!-----------------------------------------------------------------------
********************************************************************************
Copyright 2005-2007 ColdBox Framework by Luis Majano and Ortus Solutions, Corp
www.coldboxframework.com | www.luismajano.com | www.ortussolutions.com
********************************************************************************

Author 	    :	Luis Majano
Date        :	January 18, 2007
Description :
	This is a cfc that handles caching of event handlers.

Modification History:
01/18/2007 - Created

----------------------------------------------------------------------->
<cfcomponent name="cacheManager" hint="Manages handler,plugin,custom plugin and object caching. It is thread safe and implements locking for you." output="false">

<!------------------------------------------- CONSTRUCTOR ------------------------------------------->

	<cffunction name="init" access="public" output="false" returntype="cacheManager" hint="Constructor">
		<cfargument name="controller" type="any" required="true">
		<cfscript>
		variables.controller = arguments.controller;
		//Cache Configuration
		variables.CacheConfigBean = structnew();
		//Object Pool
		variables.objectPool = structnew();
		//Cache Performance
		variables.cachePerformance = structNew();
		variables.cachePerformance.Hits = 0;
		variables.cachePerformance.Misses = 0;
		//Reaping Controll
		variables.lastReapDatetime = now();
		//Init Pool
		initPool();
		//return Cache Manager;
		return this;
		</cfscript>
	</cffunction>

	<cffunction name="configure" access="public" output="false" returntype="void" hint="Configure the cache.">
		<cfargument name="cacheConfigBean" type="coldbox.system.beans.cacheConfigBean" required="true">
		<cfscript>
		//set the config bean
		variables.CacheConfigBean = arguments.cacheConfigBean;
		//Init the performance
		resetStatistics();
		</cfscript>
	</cffunction>

<!------------------------------------------- PUBLIC ------------------------------------------->

	<!--- Config Bean Setter/Getter --->
	<cffunction name="setCacheConfigBean" access="public" returntype="void" output="false">
		<cfargument name="CacheConfigBean" type="coldbox.system.beans.cacheConfigBean" required="true">
		<cfset variables.CacheConfigBean = arguments.CacheConfigBean>
	</cffunction>
	<cffunction name="getCacheConfigBean" access="public" returntype="coldbox.system.beans.cacheConfigBean" output="false">
		<cfreturn variables.CacheConfigBean >
	</cffunction>

	<!--- ************************************************************* --->

	<cffunction name="lookup" access="public" output="false" returntype="boolean" hint="Check if an object is in cache.">
		<!--- ************************************************************* --->
		<cfargument name="objectKey" type="string" required="true">
		<!--- ************************************************************* --->
		<cfset var ObjectFound = false>

		<!--- Reap the cache First, if in frequency --->
		<cfset reap()>

		<cflock type="readonly" name="OCM_Operation" timeout="5">
			<cfif getobjectPool().lookup(arguments.objectKey)>
				<cfset ObjectFound = true>
			<cfelse>
				<!--- Log miss --->
				<cfset miss()>
			</cfif>
		</cflock>
		<cfreturn ObjectFound>
	</cffunction>

	<!--- ************************************************************* --->

	<cffunction name="get" access="public" output="false" returntype="any" hint="Get an object from cache. If it doesn't exist it returns a blank structure.">
		<!--- ************************************************************* --->
		<cfargument name="objectKey" type="string" required="true">
		<!--- ************************************************************* --->
		<cfset var ObjectFound = StructNew()>

		<!--- Lookup First --->
		<cfif lookup(arguments.objectKey)>
			<!--- Record a Hit --->
			<cfset hit()>
			<cflock type="exclusive" name="OCM_Operation" timeout="5">
				<cfset ObjectFound = getobjectPool().get(arguments.objectKey)>
			</cflock>
		</cfif>
		<cfreturn ObjectFound>
	</cffunction>

	<!--- ************************************************************* --->

	<cffunction name="set" access="public" output="false" returntype="void" hint="sets an object in cache.">
		<!--- ************************************************************* --->
		<cfargument name="objectKey" 		type="string"  required="true">
		<cfargument name="MyObject"			type="any" 	   required="true">
		<cfargument name="Timeout"			type="string"  required="false" default="" hint="Timeout in minutes. If timeout = 0 then object never times out. If timeout is blank, then timeout will be inherited from framework.">
		<!--- ************************************************************* --->
		<!---JVM Threshold Checks --->
		<cfset var isBelowThreshold = ThresholdChecks()>

		<!--- Clean Args --->
		<cfset arguments.objectKey = trim(arguments.objectKey)>
		<cfset arguments.Timeout = trim(arguments.Timeout)>

		<!--- Check if we need to do a reap First. --->
		<cfset reap()>

		<!--- Max Objects in Cache Check --->
		<cfif (CacheConfigBean.getCacheMaxObjects() eq 0 or getSize() lt CacheConfigBean.getCacheMaxObjects()) and
			  (CacheConfigBean.getCacheFreeMemoryPercentageThreshold() eq 0 or isBelowThreshold)>

			<!--- Test Timeout Argument, if false, then inherit framework's timeout --->
			<cfif arguments.Timeout eq "" or not isNumeric(arguments.Timeout) or arguments.Timeout lt 0>
				<cfset arguments.Timeout = CacheConfigBean.getCacheObjectDefaultTimeout()>
			</cfif>

			<!--- Set object in Cache --->
			<cflock type="exclusive" name="OCM_Operation" timeout="5">
				<cfset getobjectPool().set(arguments.objectKey,arguments.MyObject,arguments.Timeout)>
			</cflock>
		</cfif>
	</cffunction>

	<!--- ************************************************************* --->

	<cffunction name="clearKey" access="public" output="false" returntype="boolean" hint="Clears a key from the cache.">
		<!--- ************************************************************* --->
		<cfargument name="objectKey" type="string" required="true">
		<!--- ************************************************************* --->
		<cfset var Results = false>
		<cfif lookup(arguments.objectKey) >
			<cflock type="exclusive" name="OCM_Operation" timeout="5">
				<cfset Results = getobjectPool().clearKey(arguments.objectKey)>
			</cflock>
		</cfif>
		<cfreturn Results>
	</cffunction>

	<!--- ************************************************************* --->

	<cffunction name="clear" access="public" output="false" returntype="void" hint="Clears the entire object cache.">
		<cflock type="exclusive" name="OCM_Operation" timeout="5">
			<cfset structDelete(variables,"objectPool")>
			<cfset initPool()>
			<cfset resetStatistics()>
		</cflock>
	</cffunction>

	<!--- ************************************************************* --->

	<cffunction name="resetStatistics" access="public" output="false" returntype="void" hint="Resets the cache statistics.">
		<cfscript>
		variables.cachePerformance.Hits = 0;
		variables.cachePerformance.Misses = 0;
		</cfscript>
	</cffunction>

	<!--- ************************************************************* --->

	<cffunction name="getCachePerformanceRatio" access="public" output="false" returntype="numeric" hint="Get the cache's performance ratio">
		<cfscript>
	 	var requests = variables.cachePerformance.hits + variables.cachePerformance.misses;
	 	if ( requests eq 0)
	 		return 0;
		else
			return (variables.cachePerformance.Hits/requests) * 100;
		</cfscript>
	</cffunction>

	<!--- ************************************************************* --->

	<cffunction name="getlastReapDatetime" access="public" output="false" returntype="string" hint="Get the lastReapDatetime">
		<cfscript>
		return variables.lastReapDatetime;
		</cfscript>
	</cffunction>

	<!--- ************************************************************* --->

	<cffunction name="getSize" access="public" output="false" returntype="numeric" hint="Get the cache's size in items">
		<cfscript>
		return getObjectPool().getSize();
		</cfscript>
	</cffunction>

	<!--- ************************************************************* --->

	<cffunction name="getcachePerformance" access="public" output="false" returntype="struct" hint="Get the cachePerformance structure">
		<cfscript>
		return variables.cachePerformance;
		</cfscript>
	</cffunction>

	<!--- ************************************************************* --->

	<cffunction name="getpool_metadata" access="public" returntype="struct" output="false">
		<cfreturn getObjectPool().getpool_metadata()>
	</cffunction>

	<cffunction name="getItemTypes" access="public" output="false" returntype="struct" hint="Get the item types of the cache.">
		<cfscript>
		var x = 1;
		var itemList = getObjectPool().getObjectsKeyList();
		var itemTypes = Structnew();

		//Init types
		itemTypes.plugins = 0;
		itemTypes.handlers = 0;
		itemTypes.other = 0;
		itemTypes.ioc_beans = 0;
		//Sort the listing.
		itemList = listSort(itemList, "textnocase");
		//Count objects
		for (x=1; x lte listlen(itemList) ; x = x+1){
			if ( findnocase("plugin", listGetAt(itemList,x)) )
				itemTypes.plugins = itemTypes.plugins + 1;
			else if ( findnocase("handler", listGetAt(itemList,x)) )
				itemTypes.handlers = itemTypes.handlers + 1;
			else if ( findnocase("ioc", listGetAt(itemList,x)) )
				itemTypes.ioc_beans = itemTypes.ioc_beans + 1;
			else
				itemTypes.other = itemTypes.other + 1;
		}
		return itemTypes;
		</cfscript>
	</cffunction>

	<!--- ************************************************************* --->

	<cffunction name="reap" access="public" output="false" returntype="void" hint="Reap the cache.">
		<cfscript>
			var key = "";
			var objStruct = getObjectPool().getpool_metadata();
			//Check if no data in pool
			if (not structisEmpty(objStruct)){

				//Check reaping frequency
				if ( dateDiff("n", variables.lastReapDatetime, now()) gt CacheConfigBean.getCacheReapFrequency()){
					//Reaping about to start, set new reaping date.
					variables.lastReapDatetime = now();

					//Loop Through Metadata
					for (key in objStruct){
						//Override Timeout Check
						if ( objStruct[key].Timeout gt 0 ){
							//Check for creation timeouts and clear
							if ( dateDiff("n", objStruct[key].created, now() ) gt  objStruct[key].Timeout){
								clearKey(key);
								continue;
							}
							//Check for last accessed timeout. If object has not been accessed in the default span
							if ( dateDiff("n", objStruct[key].lastAccesed, now() ) gt  CacheConfigBean.getCacheObjectDefaultLastAccessTimeout() ){
								clearKey(key);
								continue;
							}
						}
					}
				}

			}
		</cfscript>
	</cffunction>

	<!--- ************************************************************* --->

<!------------------------------------------- PRIVATE ------------------------------------------->

	<cffunction name="hit" access="private" output="false" returntype="void" hint="Record a hit">
		<cfscript>
		variables.cachePerformance.Hits = variables.cachePerformance.Hits + 1;
		</cfscript>
	</cffunction>

	<!--- ************************************************************* --->

	<cffunction name="miss" access="private" output="false" returntype="void" hint="Record a miss">
		<cfscript>
		variables.cachePerformance.misses = variables.cachePerformance.misses + 1;
		</cfscript>
	</cffunction>

	<!--- ************************************************************* --->

	<cffunction name="getObjectPool" access="private" returntype="any" output="false">
		<cfreturn variables.objectPool >
	</cffunction>

	<!--- ************************************************************* --->

	<cffunction name="initPool" access="private" output="false" returntype="void" hint="Initialize the Pool">
		<cfscript>
		variables.objectPool = CreateObject("component","objectPool").init();
		</cfscript>
	</cffunction>

	<!--- ************************************************************* --->

	<cffunction name="ThresholdChecks" access="private" output="false" returntype="boolean" hint="JVM Threshold checks">
		<cfset var fileUtilities = "">
		<cfset var check = true>
		<cfset var jvmThreshold = 0>
		<cfset var jvmFreeMemory = "">
		<cfset var jvmTotalMemory = "">
		<cftry>
			<!--- Checks --->
			<cfif CacheConfigBean.getCacheFreeMemoryPercentageThreshold() neq 0>
				<cfset fileUtilities = variables.controller.getPlugin("fileUtilities")>
				<cfset jvmFreeMemory = fileUtilities.getJVMFreeMemory()>
				<cfset jvmTotalMemory = fileUtilities.getJVMTotalMemory()>
				<cfset jvmThreshold = ((jvmFreeMemory/jvmTotalMemory)*100)>
				<cfset check = CacheConfigBean.getCacheFreeMemoryPercentageThreshold() lt jvmThreshold>
			</cfif>
			<cfcatch type="any">
				<cfset check = true>
			</cfcatch>
		</cftry>
		<cfreturn check>
	</cffunction>

</cfcomponent>