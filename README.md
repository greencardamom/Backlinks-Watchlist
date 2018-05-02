Backlinks Watchlist
===================
by User:Green Cardamom (en.wikipedia.org)
Copyright 2015, 2017
MIT License

Info
========
Backlink Watchlist monitors changes to the backlinks (aka Special:WhatLinksHere) of a 
Wikipedia page. It will email whenever new backlinks are added or deleted. It runs 
from cron, typically once a day.

BW is useful in a number of scenarios:

	1. Monitor who is linking to a Talk or AfD or RfC discussion.

	2. Monitor pages in your user space to see if anyone links to them.

	3. Monitor File: pages to see when they are added/deleted. For example, 
	   Fair Use images can be monitored for copyright violations.

	4. Monitor Templates to see when they are added/deleted from articles. 

	5. Other examples.

If someone is linking to something and you want to know about it, this will silently 
let you know.

Installation
==================

The program is a GNU Awk script. The install instructions and configuation parameters 
are at the top of the file. It will work on any Unix system that has GNU Awk 4.0+

Optionally create a symlink: ln -s bw.awk bw

Credits
==================
Want to use MediaWiki API with Awk? Check out 'MediaWiki Awk API Library' 

https://github.com/greencardamom/MediaWikiAwkAPI

