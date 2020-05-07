NAME = txt2regex
VERSION = 0.9b
BASHVERSIONS = 3.0 3.1 3.2 4.0 4.1 4.2 4.3 4.4 5.0

SHSKEL = $(NAME).sh
DISTDIR = $(NAME)-$(VERSION)
PODIR = po
POTFILE = $(PODIR)/$(NAME).pot

FILES = CHANGELOG.md COPYRIGHT Makefile man NEWS $(PODIR) \
        README.japanese README.md $(SHSKEL) tests TODO

DESTDIR =
BINDIR = $(DESTDIR)/usr/bin
LOCALEDIR = $(DESTDIR)/usr/share/locale
MANDIR = $(DESTDIR)/usr/share/man/man1

.PHONY: check check-po clean doc fmt install install-bin \
        install-mo lint mo po pot test test-bash test-regex \
        test-regex-build test-regex-shell tgz

#-----------------------------------------------------------------------
# Dev

check: lint test

fmt:
	shfmt -w -i 4 -ci -sr $(SHSKEL) tests/regex-tester.sh

lint:
	shellcheck $(SHSKEL) tests/regex-tester.sh
	shfmt -d -i 4 -ci -sr tests/regex-tester.sh

test: clitest.sh
	sh clitest.sh --progress none README.md tests/*.md

# Run the tests in multiple Bash versions (each Docker image is ~10MB)
test-bash: clitest.sh
	@for v in $(BASHVERSIONS); do \
		printf '\nTesting in Bash version %s\n' $$v; \
		docker run --rm -v $$PWD:/code -w /code bash:$$v \
			sh clitest.sh --progress none tests/*.md; \
	done

# Run regex tests for the supported programs, inside a Docker container
test-regex: test-regex-build
	docker run --rm -v "$$PWD":/code -w /code regex-tester \
		tests/regex-tester.sh --skip vi > tests/regex-tester.txt 2>&1
	# vi: no stderr redirect to avoid "inappropriate ioctl for device"
	# vi: docker run -t adds a trailing \r to every line :/
	docker run --rm -v "$$PWD":/code -w /code -t regex-tester \
		tests/regex-tester.sh vi | tr -d '\r' >> tests/regex-tester.txt

test-regex-shell: test-regex-build
	docker run --rm -v "$$PWD":/code -w /code -it regex-tester

test-regex-build:
	docker build -t regex-tester tests/

clean:
	rm -f clitest.sh $(NAME) txt2tags.py
	rm -f messages.mo $(PODIR)/{messages,*.mo,*.tmp,*~}
	rm -rf $(PODIR)/??/ $(PODIR)/??_??/
	rm -f tmp.lex.*.{l,run,yy.c}

doc: txt2tags.py
	@python ./txt2tags.py -t man  man/txt2regex.t2t
	@python ./txt2tags.py -t html man/txt2regex.t2t

clitest.sh:
	curl -s -L -o $@ \
	https://raw.githubusercontent.com/aureliojargas/clitest/master/clitest

txt2tags.py:
	curl -s -L -o $@ \
	https://raw.githubusercontent.com/aureliojargas/txt2tags/3.4/txt2tags.py

#-----------------------------------------------------------------------
# Translation files
#
# Learn more: http://pology.nedohodnik.net/doc/user/en_US/ch-poformat.html
# Example potfile: http://git.savannah.gnu.org/cgit/gawk.git/tree/po/gawk.pot

pot:
	@date=`date '+%Y-%m-%d %H:%M %Z'`; \
	( \
		printf '%s\n' '#, fuzzy'; \
		printf '%s\n' 'msgid ""'; \
		printf '%s\n' 'msgstr ""'; \
		printf '"%s"\n' 'Project-Id-Version: $(NAME) $(VERSION)\n'; \
		printf '"%s"\n' "POT-Creation-Date: $$date\n"; \
		printf '"%s"\n' 'PO-Revision-Date: YEAR-MO-DA HO:MI+ZONE\n'; \
		printf '"%s"\n' 'Last-Translator: FULL NAME <EMAIL@ADDRESS>\n'; \
		printf '"%s"\n' 'MIME-Version: 1.0\n'; \
		printf '"%s"\n' 'Content-Type: text/plain; charset=UTF-8\n'; \
		printf '"%s"\n' 'Content-Transfer-Encoding: 8bit\n'; \
		bash --dump-po-strings $(SHSKEL); \
	) | msguniq --no-wrap --sort-by-file -o $(POTFILE); \
	printf '%s was generated\n' $(POTFILE)

po: pot
	@for pofile in $(PODIR)/*.po; do \
		printf 'Merging %s...' $$pofile; \
		msgmerge --update --sort-by-file --no-wrap --previous \
			$$pofile $(POTFILE); \
	done; \
	printf 'Remember to grep for the fuzzy messages in all .po files\n'

mo:
	@for pofile in $(PODIR)/*.po; do \
		printf 'Compiling %s... ' $$pofile; \
		msgfmt -o $${pofile%.po}.mo $$pofile && \
		echo ok; \
	done

check-po:
	@for pofile in $(PODIR)/*.po; do \
		printf 'Checking %s...' $$pofile; \
		msgfmt --verbose $$pofile || exit 1; \
	done

#-----------------------------------------------------------------------
# Release

tgz: clean check doc
	mkdir -p $(DISTDIR) && \
	cp -a $(FILES) $(DISTDIR) && \
	tar cvzf $(DISTDIR).tgz $(DISTDIR) && \
	rm -rf $(DISTDIR) && \
	printf '\nSuccessfully created %s\n' $(DISTDIR).tgz

install: install-mo install-bin

install-mo: mo
	test -d $(LOCALEDIR) || mkdir -p $(LOCALEDIR); \
	for mofile in $(PODIR)/*.mo; do \
		moinstalldir=$(LOCALEDIR)/`basename $$mofile .mo`/LC_MESSAGES; \
		test -d $$moinstalldir || mkdir -p $$moinstalldir; \
		install -m644 $$mofile $$moinstalldir/$(NAME).mo; \
	done

install-bin:
	test -d $(BINDIR) || mkdir -p $(BINDIR); \
	sed -e '/^TEXTDOMAINDIR=/s,=.*,=$(LOCALEDIR),' \
		-e '/^VERSION=/s/=.*/=$(VERSION)/' \
		$(SHSKEL) > $(BINDIR)/$(NAME) && \
	chmod +x $(BINDIR)/$(NAME) && \
	printf '\nProgram "%s" installed. Just run %s\n' \
		$(NAME) $(BINDIR)/$(NAME)
