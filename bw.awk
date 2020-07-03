#!/bin/awk -bE

# Backlinks Watchlist - monitor articles, templates etc.. on Wikipedia and email
#                       when they are added-to or deleted-from other articles.
#
# https://github.com/greencardamom/Backlinks-Watchlist
# Copyright (c) User:Green Cardamom (on en.wikipeda.org)
# December 2016
# License: MIT 
#
# History:
#
#    03 Jul 2020  - Add support for "MAXLAGERROR"
#    01 Jul 2020  - Bug fix in uniq()
#    30 Jun 2020  - Bug fix in join2() and uniq()
#    01 Dec 2016  - Add shquote(), urlencodeawk() .. made safe for article names with unusual characters
#                   Add apierror()  
#                   Bug fix in &iucontinue (missing)
#                   Change to awk -bE
#    19 Nov 2015  - Bug fix: wrongly reports deletions of transcluded entities after a page blank
#                            due to Wiki database update lags. New functions subtractions(), regstr() and regesc()
#    10 Nov 2015  - Support for G["maxlag"] variable
#                   Bug fix: broke when maxlag timed out. 
#                   New debug() function.
#    25 Aug 2015  - Expanded support for "File:" and "Template:" type backlinks. 
#                   Re-write backlinks() function
#                   New uniq() and getbacklinks() function
#    22 Aug 2015  - Bug fix: missing ")"
#    19 Aug 2015  - Support for "File:" type backlinks
#                   Bug fix: broke when maxlag timed out. (fix didn't work see 10 Nov )
#    12 Jun 2015  - Change networking agent to wget due to MediWiki conversion to SSL (Gawk lacks SSL)
#    14 May 2015  - First version.
#

BEGIN{

# ====================== Configuration Variables & Install Instructions ============================== #
#
# Dependencies: GNU awk 4.0+
#               POSIX grep such as GNU (older systems try fgrep)
#
# Install:  1. Create a directory called "bw". Save this file there, name it "bw" and 
#                set executable ("chmod 755 bw")
#
#           2. Change the first line #!/.. path to where GNU awk is located on your system. 
#
#           3. Set the following configuration variables G["path"] (directory where this file is) 
#               and G["email"] (an email address to send script output):

G["path"]  = "/home/path/bw/"
G["email"] = "yourname@localhost"

#           4. Create bw.cfg containing a list of "entities" to monitor. Example:
#
#		 Template:Librivox book
#		 User talk:Jimbo Wales
#		 Wikipedia:Articles for deletion/George Zimmerman
#		 File:Gerald Stanley Lee at his Driftwood Desk 8-18-1941.jpg
#		 etc..
#
#	    5. Set default backlink types. The below G["types"] string means only article namespace backlinks are monitored.
#               In other words, if a given backlink is not an article page (such as a Talk page or Category), it will be ignored. 
#               If you're happy with this do nothing. 
#               However, if you want to monitor article backlinks + User talk page backlinks, remove the section
#                   |^User talk: 
#               from the G["types"] string. To monitor all backlink types, set G["types"] = "ALL"

G["types"] = "(^Talk:|^Wikipedia:|^Wikipedia talk:|^Template:|^Template talk:|^Portal:|^Portal talk:|^User:|^User talk:|^File:|^File talk:|^MediaWiki:|^MediaWiki talk:|^Help:|^Help talk:|^Category:|^Category talk:|^Portal:|^Portal talk:|^Book:|^Book talk:|^Draft:|^Draft talk:|^TimedText:|^TimedText talk:|^Module:|^Module talk:)"
# G["types"] = "ALL"

#           6. You can also customize backlink types on a per-entity basis. If set, will take precedance over 
#               the default setting in step 5. for that entity only. For example to monitor ALL for 
#               "Template:Gutenberg author", set T below.
#               You can add multiple T lines, one for each entity. 

# T["Template:Gutenberg author"] = "ALL"
# T["Template:Internet Archive"] = "(^Portal:)"

#               The second example means that all backlinks types except those in the Portal: namespace will be 
#               monitored for Template:Internet Archive
#
#           7. Test by running "./bw"
#                If trouble, set G["debug"] = "yes"  - default output = "debug.out" in current directory

G["debug"] = "no"
G["debugout"] = G["path"] "/debug.out"

#           8. Maxlag - adjust if too many MediWiki API timeout errors. Default: 5
#                       documentation: https://www.mediawiki.org/wiki/Manual:Maxlag_parameter
#

G["maxlag"] = 5

#           9. Add bw to your crontab. Check daily or whenever desired:
#
# 		 10 6 * * * /home/myaccount/bw/bw >> /dev/null 2>&1            
#
#              The crontab also needs the following (or similar) at the top if not already:
#                SHELL=/bin/sh  
#                PATH=/sbin:/bin:/usr/sbin:/usr/local/bin:/usr/bin 
#                MAILTO=myaccount@localhost
#                LANG=en_US.UTF-8
#                LC_COLLATE=en_US.UTF-8
#              Without these the results of bw will be intermittent or not work. LANG and LC_COLATE
#              can be whatever your location is, this example is the US. SHELL and PATH can be whatever
#              your shell and paths are.
#
#            10. An API agent string. Can be whatever, typically your contact info and name of program.

G["api agent"] = "Backlinks Watchlist (User:Green_Cardamom on en)"

#
#           END CONFIGURATION 
#
# ====================================================================================== #
#
        debug("\n\t\t\t================ " strftime("%Y-%m-%d- %H:%M:%S") " =================")

        G["files_system"] = "grep wget mail cp rm mv"
        G["files_local"]  = "bw bw.cfg"
        G["cfgfile"]      = "bw.cfg"
        G["max"]          = 100         # Max changes to include in an email alert

        if ( substr(G["path"],length(G["path"]) ) != "/")
            G["path"] = G["path"] "/"

        setup(G["files_system"], G["files_local"], G["path"])

        main(sprintf("%s%s",G["path"],G["cfgfile"]))
}

function main(cfgfile		,V ,name, br) {

        while ((getline name < cfgfile) > 0) {

            delete V

            debug("\t======= " name " =======")

            V["newflag"] = 0
            V["name"]  = strip(name)
            G["name"]  = V["name"]
            V["fname"] = V["name"]
            gsub("/", "-", V["fname"])  
            V["oldtxt"] = G["path"] V["fname"] ".old"
            V["otptxt"] = G["path"] V["fname"] ".otp" 
            V["newtxt"] = G["path"] V["fname"] ".new"
            V["addtxt"] = G["path"] V["fname"] ".add"
            V["subtxt"] = G["path"] V["fname"] ".sub"
            V["emailtxt"] = sprintf("  Backlinks Watchlist\n  ------------------------------\n")

            if ( file_exists(V["oldtxt"]) )
                sys2var("cp -- " shquote(V["oldtxt"]) " " shquote(V["otptxt"]) )
            if ( file_exists(V["newtxt"]) ) 
                sys2var("mv -- " shquote(V["newtxt"]) " " shquote(V["oldtxt"]) ) 
            else {                 # New entity 
                if( entity_exists(V["name"]) ) {
                    printf("") > V["oldtxt"]
                    printf("") > V["otptxt"]
                    close(V["oldtxt"]) 
                    close(V["otptxt"]) }
                else                 
                    continue
            }
        
            br = backlinks(V["name"], V["newtxt"])

            debug("raw backlinks = " br)
  
            if ( br == -1 || br == 0 || br == "" ) {  # entity has maxlag error (-1) or no entries (0). Restore files, email if maxlag.
                sys2var("mv -- " shquote(V["oldtxt"]) " " shquote(V["newtxt"]) )
                sys2var("mv -- " shquote(V["otptxt"]) " " shquote(V["oldtxt"]) )
                if(br == -1) {
                  V["emailtxt"] = V["emailtxt"] "\nNo backlinks found for " G["name"] " - aborting.\n\nPossibly Maxlag exceeded. Try again when API server is less busy or modify G[\"maxlag\"] variable in script."
                  V["command"] = sprintf("mail -s 'Warning: Backlinks at Wikipedia ('%s')' -- %s", shquote(V["name"]), G["email"])
                  print V["emailtxt"] | V["command"]
                  close(V["command"])
                }
                continue
            } else {
                if ( file_exists(V["otptxt"]) ) { # all is good, cleanup 
                    close(V["otptxt"])
                    sys2var("rm -r -- " shquote(V["otptxt"]) )
                }
            }
              
            V["additions"]    = sys2var("grep -vxFc -f " shquote(V["oldtxt"]) " -- " shquote(V["newtxt"]))
            V["subtractions"] = sys2var("grep -vxFc -f " shquote(V["newtxt"]) " -- " shquote(V["oldtxt"]))

            if ( V["additions"] ) {
              V["newflag"] = 1
              V["emailtxt"] = V["emailtxt"] sprintf("  %s new backlinks for %s\n", V["additions"], V["name"]) 
            }

            if ( V["additions"] ) {
                if ( V["additions"] < G["max"] ) {
                    V["emailtxt"] = V["emailtxt"] sprintf("\n  Additions (added to %s ):\n\n", V["addtxt"])
                    V["out"] = sys2var("grep -vxF -f " shquote(V["oldtxt"]) " -- " shquote(V["newtxt"]))
                    V["emailtxt"] = V["emailtxt"] V["out"] "\n\n"
                    print V["out"] >> V["addtxt"] }
                else {
                    V["emailtxt"] = V["emailtxt"] sprintf("\n  Additions over %s\n   List not sent in email nor added to %s\n   To see changes:\n\n", G["max"], V["addtxt"])
                    V["emailtxt"] = V["emailtxt"] "grep -vxF -f " shquote(V["oldtxt"]) " -- " shquote(V["newtxt"]) "\n\n"
                }
            }        
            if ( V["subtractions"] ) {
                if ( V["subtractions"] < G["max"] ) {
                    V["out"] = subtractions(V["name"], V["newtxt"], V["oldtxt"])
                    V["subtractions"] = countstr(V["out"], "\n")
                    if ( V["subtractions"] > 0 ) {
                        V["newflag"] = 1
                        V["emailtxt"] = V["emailtxt"] sprintf("  %s deleted backlinks for %s\n", V["subtractions"], V["name"])
                        V["emailtxt"] = V["emailtxt"] sprintf("\n  Deletions (added to %s ):\n\n", V["subtxt"])
                        V["emailtxt"] = V["emailtxt"] V["out"] "\n\n"
                        print V["out"] >> V["subtxt"]
                    }
                }
                else {
                    V["emailtxt"] = V["emailtxt"] sprintf("\n  Deletions over %s\n   List not sent in email nor added to %s\n   To see changes:\n\n", G["max"], V["subtxt"])
                    V["emailtxt"] = V["emailtxt"] "grep -vxF -f " shquote(V["newtxt"]) " -- " shquote(V["oldtxt"]) "\n\n"
                }
            }        

            if ( V["newflag"] ) {
                close(V["addtxt"])
                close(V["subtxt"])
                V["command"] = sprintf("mail -s 'New Backlinks at Wikipedia ('%s')' -- %s", shquote(V["name"]), G["email"])
                print V["emailtxt"] | V["command"]
                close(V["command"])
            }
        }   


}

#
# backlinks - backlinks for a Wikipedia page (article, Template:, User:, Category:, etc..)
#
#  example: backlinks("Template:Gutenberg author", "out.txt")
#           where "out.txt" is the name of a file to save the list to.
#
#  return 0 if no links found (0 may or may not mean entity exists, see entity_exists() )
#
function backlinks(entity, outfile      ,url, blinks) {

        url = "http://en.wikipedia.org/w/api.php?action=query&list=backlinks&bltitle=" urlencodeawk(entity) "&blredirect&bllimit=250&continue=&blfilterredir=nonredirects&format=json&utf8=1&maxlag=" G["maxlag"]
        blinks = getbacklinks(url, entity, "blcontinue") # normal backlinks

        if ( entity ~ "^Template:") {    # transclusion backlinks
            url = "http://en.wikipedia.org/w/api.php?action=query&list=embeddedin&eititle=" urlencodeawk(entity) "&continue=&eilimit=500&continue=&format=json&utf8=1&maxlag=" G["maxlag"]
            blinks = blinks "\n" getbacklinks(url, entity, "eicontinue")
        } else if ( entity ~ "^File:") { # file backlinks
            url = "http://en.wikipedia.org/w/api.php?action=query&list=imageusage&iutitle=" urlencodeawk(entity) "&iuredirect&iulimit=250&continue=&iufilterredir=nonredirects&format=json&utf8=1&maxlag=" G["maxlag"]
            blinks = blinks "\n" getbacklinks(url, entity, "iucontinue")
        }

        blinks = uniq(blinks, entity)
        if(length(blinks) > 0 && blinks != "MAXLAGERROR")
          print blinks > outfile
        close(outfile)
        if(blinks == "MAXLAGERROR")
          return -1
        return length(blinks)

}
function getbacklinks(url, entity, method,      jsonin, jsonout, continuecode) {

        jsonin = http2var(url)
        if(apierror(jsonin, "json") > 0)
          return ""
        jsonout = json2var(jsonin)
        continuecode = getcontinue(jsonin, method)

        while ( continuecode ) {

            if ( method == "eicontinue" )
                url = "http://en.wikipedia.org/w/api.php?action=query&list=embeddedin&eititle=" urlencodeawk(entity) "&eilimit=500&continue=" urlencodeawk("-||") "&eicontinue=" urlencodeawk(continuecode) "&format=json&utf8=1&maxlag=" G["maxlag"]
            if ( method == "iucontinue" )
                url = "http://en.wikipedia.org/w/api.php?action=query&list=imageusage&iutitle=" urlencodeawk(entity) "&iuredirect&iulimit=250&continue=" urlencodeawk("-||") "&iufilterredir=nonredirects&iucontinue=" urlencodeawk(continuecode) "&format=json&utf8=1&maxlag=" G["maxlag"]
            if ( method == "blcontinue" )
                url = "http://en.wikipedia.org/w/api.php?action=query&list=backlinks&bltitle=" urlencodeawk(entity) "&blredirect&bllimit=250&continue=" urlencodeawk("-||") "&blcontinue=" urlencodeawk(continuecode) "&blfilterredir=nonredirects&format=json&utf8=1&maxlag=" G["maxlag"]

            jsonin = http2var(url)
            jsonout = jsonout "\n" json2var(jsonin)
            continuecode = getcontinue(jsonin, method)
        }

        return jsonout
}
function getcontinue(jsonin, method	,re,a,b,c) {

	# "continue":{"blcontinue":"0|20304297","continue"

        re = "\"continue\"[:][{]\"" method "\"[:]\"[^\"]*\""
        match(jsonin, re, a)
        split(a[0], b, "\"")
        
        if ( length(b[6]) > 0) 
            return b[6]
        return 0                  
}

#
#        subtractions - workaround for a bug (feature): Wikipedia database lag
#                        For example, if an article is blanked by a vandal and a bot restores
#                        it seconds later, the template backlinks (transclusions) may take days to be
#                        restored due to lags in the wikipedia database, thus falsely reporting a deletion.
#                        This will verify if the template is in fact in the article by doing a RegExp search of the wikisource.
#
function subtractions(entity, newtext, oldtext,

        list,c,a,i,page,first,out,first2,out2) {

        if(entity ~ /[Tt]emplate:|[Ff]ile:/) { # transclusions known to have database lags. Add others if seeing.
            list = sys2var("grep -vxF -f " shquote(newtext) " -- " shquote(oldtext) )
            c = split(list, a, "\n")
            while(i++ < c) {
                # Get wikisource of article where the entity was reportedly deleted
                page = http2var("https://en.wikipedia.org/w/index.php?title=" urlencodeawk(a[i]) "?action=raw")
                # RE search article for entity. Include in deletion list if not found.
                if(page !~ regstr(entity)) {
                    if(first == 0) {
                        out = a[i]
                        first = 1
                    }
                    else {
                        out = out "\n" a[i]
                    }
                }
                else { # add article names back to newtext
                    if(first2 == 0 ) {
                        out2 = a[i]
                        first2 = 1
                    }
                    else {
                        out2 = out2 "\n" a[i]
                    }
                    debug("Warning (database update lag): entity \"" entity "\" is not in the backlinks of article \"" a[i] "\" but was found in the article wikisource. Not marked deleted.")
                }
            }
            if(length(out2) > 0) {
                print out2 >> newtext
                close(newtext)
            }
            return out
        }
        else {
            return sys2var("grep -vxF -f " shquote(newtext) " -- " shquote(oldtext) )
        }
}
#
# Build a RE for finding entity in wikisource
#
function regstr(entity,

        a,c,entityname,bracketopen,bracketclose,namespace,re) {

        bracketopen = "[[]"
        bracketclose = "[]]"
        c = split(entity,a,":")
        entityname = regesc(strip(join(a,2,c,":")))
        namespace = ""
        if(entity ~ /^[Tt]emplate:/) {
            bracketopen  = "[{]"
            bracketclose = "[}]"
        }
        else if(entity ~ /^[Ff]ile:/) {
            bracketopen = ""
            bracketclose = ""
        }
        else if(entity ~ /^[Ww]ikipedia:|^[Ww][Pp]:/) {
            namespace = "(Wikipedia|WP):"
        }
        else {
            entityname = regesc(strip(entity))
        }

        re = bracketopen "[ ]{0,2}" namespace entityname "[ ]{0,2}([|]|" bracketclose ")"

        return re
}
#
# Regex escapes. Change "Dr." to "Dr[.]" .. Change "gutenberg" to "[Gg]utenberg"
#
function regesc(var,    c,a,i,out){

        c = split(var,a,"")
        while(i++ < c) {
            if(i == 1) {
                if(a[i] ~ /[[:alpha:]]/)
                    out = "[" toupper(a[i]) tolower(a[i]) "]"
                else
                    out = a[i]
                continue
            }
            out = out a[i]
        }

        #gsub("[[]","[[]",out) #don't
        #gsub("[]]","[]]",out) #don't
        #gsub("[^]","[^]",out) #? error
        #gsub("[\]","[\]",out) #? error
        gsub("[.]","[.]",out)
        gsub("[?]","[?]",out)
        gsub("[*]","[*]",out)
        gsub("[(]","[(]",out)
        gsub("[)]","[)]",out)
        gsub("[$]","[$]",out)
        gsub("[|]","[|]",out)
        gsub("[+]","[+]",out)

        return out
}

#
# entity_exists - see if a page on Wikipedia exists
#   eg. if ( ! entity_exists("Gutenberg author") ) print "Unknown page"
#
function entity_exists(entity	,url,jsonin) {

        url = "https://en.wikipedia.org/w/api.php?action=query&titles=" urlencodeawk(entity) "&format=json"
        jsonin = http2var(url)
        if(jsonin ~ "\"missing\"") 
            return 0
        return 1
}


#
# Check for existence of needed programs and files.
#   
function setup(files_system, files_local, b_path) {

        if ( ! files_verify("ls","",b_path) ) {
            printf("Unable to find ls. Please ensure your crontab has paths set eg.:PATH=/sbin:/bin:/usr/sbin:/usr/local/bin:/usr/bin\n")
            exit          
        }
        if ( ! sys2var(sprintf("ls -d %s",b_path)) ) {
            printf("Unable to find directory %s\nPlease configure path in the first lines of the source file.\n",b_path)
            exit
        }
        if ( ! files_verify(files_system, files_local, b_path) ) {
            exit
        }
}

#
# Verify existence of programs in path, and files in a local directory
#   eg. files_verify("diff uniq sort", "tbm.cfg", "/home/green")
# first parameter is list of files needed in path
# second (optional) is needed files in local directory.
# third (optional) is the local dir.
# Return 0 if fail. 
#
function files_verify(files_system, files_local, localdir,
        a,i,emailtext,command,missing) {

        emailtext = "\n"
	missing = 0
        split(files_system, a, " ")
        for ( i in a ) {
            if ( ! sys2var(sprintf("command -v %s",a[i])) ) {
                missing++
                print "Abort: command not found in PATH: " a[i] 
                emailtext = emailtext sprintf("Abort: command not found in PATH: %s\n", a[i])
            }
        }
        if ( files_local && localdir ) {
            split(files_local, a, " ")
            if ( substr(localdir,length(localdir)) != "/" )
                localdir = localdir "/"
            i = 0
            for ( i in a ) {
                if ( ! file_exists(localdir a[i]) ) {
                    missing++
                    print "Abort: file not found in " localdir ": " a[i] 
                    emailtext = emailtext sprintf("Abort: file not found in %s: %s\n", localdir, a[i])
                }
            }
        }
        if ( missing ) {
            if ( G["email"] ~ "@" ) {
                command = sprintf("mail -s \"Error in Backlinks Watchlist\" -- %s", G["email"])
                print emailtext | command
                close(command)
            }
            return 0
        }
        return 1
}

#
# Run a system command and store result in a variable
#   eg. googlepage = sys2var("wget -q -O- http://google.com")
# Supports pipes inside command string. Stderr is sent to null.
# If command fails return null
#
function sys2var(command        ,catch, weight, ship) {

         debug("command= " command)

         command = command " 2>/dev/null"
         while ( (command | getline catch) > 0 ) {
             if ( ++weight == 1 )
                 ship = catch
             else
                 ship = ship "\n" catch
         }
         close(command)
         return ship
}

#
# Webpage to variable
#
function http2var(url) {

        return sys2var("wget --no-check-certificate --user-agent=" shquote(G["api agent"]) " -q -O- -- " shquote(url) )

}

#
# empty() - return 0 if string is 0-length
#
function empty(s) {
    if (length(s) == 0)                
        return 1       
    return 0
}

#
# Check if file exists, even zero-length.
#   eg. if(! file_exists(filename)) {print "not exist"}
#
function file_exists(file    ,line)
{
        if ( (getline line < file) == -1 ) {
                close(file)
                return 0 }
        else {
                close(file)
                return 1
        }
}

#
# Uniq a list of \n separated names obtained from Wikipedia API
#
function uniq(names,entity,    b,c,i,x,ok) {

        delete x
        c = split(names, b, "\n")
        names = "" # free memory
        for(i = 1; i <= c; i++) {
            gsub(/\\["]/,"\"",b[i])      # convert \" to "
            if(b[i] ~ "for API usage") { # Max lag exceeded.
                print "Max lag exceeded for " G["name"] " - aborting. Try again when API servers less busy or increase Maxlag." > "/dev/stderr"
                debug("Warning (max lag exceeded): For " G["name"] " - aborting. Try again when API servers less busy or increase Maxlag.")
                return "MAXLAGERROR"
            }
            if(b[i] == "")
                continue

            ok = 0
            if(!empty(T[entity])) {
              if(T[entity] == "ALL")
                ok = 2
              else
                ok = 3
            }
            else {
              if(G["types"] == "ALL")
                ok = 2
              else if(empty(G["types"]))
                ok = 0
              else
                ok = 1
            }
            if(ok > 0) {
              if(ok == 2) {
                if(x[b[i]] == "")
                    x[b[i]] = b[i]
              }
              if(ok == 3) {
                if(b[i] !~ T[entity]) {
                  if(x[b[i]] == "")
                      x[b[i]] = b[i]
                }
              }
              if(ok == 1) {
                if(b[i] !~ G["types"]) {
                  if(x[b[i]] == "")
                      x[b[i]] = b[i]
                }
              }
            }
        }
        delete b # free memory
        return join2(x,"\n")
}

#
# Strip leading/trailing whitespace
#
function strip(str)
{
        gsub(/^[[:space:]]+|[[:space:]]+$/,"",str)
        return str
}

#
# Merge an array of strings into a single string. Array indice are numbers.
#
function join(array, start, end, sep,    result, i)
{

    result = array[start]
    for (i = start + 1; i <= end; i++) 
        result = result sep array[i]
    return result
}

#
# Merge an array of strings into a single string. Array indice are strings.
#
function join2(arr, sep         ,i,lobster,result) {

        for ( lobster in arr ) {
            if(++i == 1) {
                result = lobster
                continue
            }
            result = result sep lobster
        }
        return result
}

#
# Count elements in a string along div boundary
#
function countstr(str, div,   a) {
    return split(str, a, div)
}


#
# Basic check of API results for error
#
function apierror(input, type) {

        if(length(input) < 5) {
          return 1
        }                  

        if(type == "json") {
          if(match(input, /"error"[:]{"code"[:]"[^\"]*","info"[:]"[^\"]*"/, code) > 0) {
            return 1
          }
        }
        else if(type == "xml") {
          if(match(input, /error code[=]"[^\"]*" info[=]"[^\"]*"/, code) > 0) {
            return 1
          }
        }
        else
          return
}

#
# Percent encode a string for use in a URL
#  Credit: Rosetta Code May 2015
#  GNU Awk needs -b to encode extended ascii eg. "ł"
#
function urlencodeawk(str,  c, len, res, i, ord) {

        for (i = 0; i <= 255; i++)
                ord[sprintf("%c", i)] = i
        len = length(str)      
        res = ""
        for (i = 1; i <= len; i++) {
                c = substr(str, i, 1);
                if (c ~ /[0-9A-Za-z]/)
                        res = res c
                else
                        res = res "%" sprintf("%02X", ord[c])
        }           
        return res
}        

#
# Make string safe for shell  
# 
function shquote (str,  safe) {    
        safe = str
        gsub(/'/, "'\\''", safe)
        gsub(/’/, "'\\’'", safe)
        return "'" safe "'"
}


#
# Print debug to file G["debugout"]
#
function debug(str){

    if ( G["debug"] == "yes" ) {
        print str >> G["debugout"]
        close(G["debugout"])
    }
}


# =====================================================================================================
# JSON parse function. Returns a list of values parsed from json data.
#   example:  jsonout = json2var(jsonin)
# Returns a string containing values separated by "\n".
# See the section marked "<--" in parse_value() to customize for your application.
#
# Credits: by User:Green Cardamom at en.wikipedia.org
#          JSON parser derived from JSON.awk
#          https://github.com/step-/JSON.awk.git
# MIT license. May 2015        
# =====================================================================================================
function json2var(jsonin) {

        TOKEN=""
        delete TOKENS
        NTOKENS=ITOKENS=0
        delete JPATHS
        NJPATHS=0
        VALUE=""

        tokenize(jsonin)

        if ( parse() == 0 ) {
          return join(JPATHS,1,NJPATHS, "\n")
        }
}
function parse_value(a1, a2,   jpath,ret,x) {
        jpath=(a1!="" ? a1 "," : "") a2 # "${1:+$1,}$2"
        if (TOKEN == "{") {
                if (parse_object(jpath)) {
                        return 7
                }
        } else if (TOKEN == "[") {
                if (ret = parse_array(jpath)) {
                        return ret
        }
        } else if (TOKEN ~ /^(|[^0-9])$/) {
                # At this point, the only valid single-character tokens are digits.
                return 9
        } else {
                VALUE=TOKEN
        }
        if (! (1 == BRIEF && ("" == jpath || "" == VALUE))) {

                # This will print the full JSON data to help in building custom filter
              #   x = sprintf("[%s]\t%s", jpath, VALUE)
              #   print x

                if ( a2 == "\"*\"" || a2 == "\"title\"" ) {     # <-- Custom filter for MediaWiki API. Add custom filters here.
                    x = substr(VALUE, 2, length(VALUE) - 2)
                    NJPATHS++
                    JPATHS[NJPATHS] = x
                }

        }
        return 0
}
function get_token() {
        TOKEN = TOKENS[++ITOKENS] # for internal tokenize()
        return ITOKENS < NTOKENS
}
function parse_array(a1,   idx,ary,ret) {
        idx=0
        ary=""
        get_token()
        if (TOKEN != "]") {
                while (1) {
                        if (ret = parse_value(a1, idx)) {
                                return ret
                        }
                        idx=idx+1
                        ary=ary VALUE
                        get_token()
                        if (TOKEN == "]") {
                                break
                        } else if (TOKEN == ",") {
                                ary = ary ","
                        } else {
                                return 2
                        }
                        get_token()
                }
        }
        VALUE=""
        return 0
}
function parse_object(a1,   key,obj) {
        obj=""
        get_token()
        if (TOKEN != "}") {
                while (1) {
                        if (TOKEN ~ /^".*"$/) {
                                key=TOKEN
                        } else {
                                return 3
                        }
                        get_token()
                        if (TOKEN != ":") {
                                return 4
                        }
                        get_token()
                        if (parse_value(a1, key)) {
                                return 5
                        }
                        obj=obj key ":" VALUE
                        get_token()
                        if (TOKEN == "}") {
                                break
                        } else if (TOKEN == ",") {
                                obj=obj ","
                        } else {
                                return 6
                        }
                        get_token()
                }
        }
        VALUE=""
        return 0
}
function parse(   ret) {
        get_token()
        if (ret = parse_value()) {
                return ret
        }
        if (get_token()) {
                return 11
        }
        return 0
}
function tokenize(a1,   myspace) {

        # POSIX character classes (gawk) 
        # Replaced regex constant for string constant, see https://github.com/step-/JSON.awk/issues/1
        myspace="[[:space:]]+"
        gsub(/\"[^[:cntrl:]\"\\]*((\\[^u[:cntrl:]]|\\u[0-9a-fA-F]{4})[^[:cntrl:]\"\\]*)*\"|-?(0|[1-9][0-9]*)([.][0-9]*)?([eE][+-]?[0-9]*)?|null|false|true|[[:space:]]+|./, "\n&", a1)
        gsub("\n" myspace, "\n", a1)
        sub(/^\n/, "", a1)
        ITOKENS=0 
        return NTOKENS = split(a1, TOKENS, /\n/)

}

