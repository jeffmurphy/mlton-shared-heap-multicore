## Copyright (C) 1999-2005 Henry Cejtin, Matthew Fluet, Suresh
 #    Jagannathan, and Stephen Weeks.
 # Copyright (C) 1997-2000 NEC Research Institute.
 #
 # MLton is released under a BSD-style license.
 # See the file MLton-LICENSE for details.
 ##

TEX_FILES := \
	abstract.tex		\
	main.tex		\
	macros.tex		\

FIG_FILES := \

all:	main.ps

# -verbosity 0  be quieter (but not quiet enough for my taste)
# -address ''	puts no author address at the bottom of each page

main/main.html: $(TEX_FILES)
	latex2html -verbosity 1 -address '' -local_icons main.tex
	cd main && rm -f WARNINGS images.* *.pl
	cd main && rm -f index.html && ln -s main.html index.html

main.dvi: $(TEX_FILES) $(FIG_FILES)
	latex main; bibtex main; latex main; latex main

main.ps: main.dvi
	dvips -o main.ps main

%.ps: %.fig
	fig2dev -Leps $< $@

.PHONY: clean
clean:
	../../bin/clean

.PHONY: tags
tags:
	etags *.tex
