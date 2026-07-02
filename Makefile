OCAMLOPT = ocamlopt
OCAMLYACC = ocamlyacc
OCAMLLEX = ocamllex
OCAMLC = ocamlc

FLAGS = -w -20

SRCDIR = src
OBJDIR = _build

# Source files
LEXER = $(SRCDIR)/lexer.mll
PARSER = $(SRCDIR)/parser.mly
SOURCES = $(SRCDIR)/main.ml $(SRCDIR)/semantic.ml $(SRCDIR)/codegen.ml

# Generated files
LEXER_ML = $(SRCDIR)/lexer.ml
PARSER_ML = $(SRCDIR)/parser.ml
PARSER_MLI = $(SRCDIR)/parser.mli

# Object files
OBJS = $(SRCDIR)/parser.cmx $(SRCDIR)/lexer.cmx $(SRCDIR)/semantic.cmx $(SRCDIR)/codegen.cmx $(SRCDIR)/main.cmx
PARSER_CMI = $(SRCDIR)/parser.cmi

# Executable
EXECUTABLE = pclc

.PHONY: all clean distclean

all: $(EXECUTABLE)

$(EXECUTABLE): $(LEXER_ML) $(PARSER_ML) $(OBJS)
	$(OCAMLOPT) $(FLAGS) -o $@ $(OBJS)

$(LEXER_ML): $(LEXER) $(PARSER_MLI)
	$(OCAMLLEX) -o $@ $<

$(PARSER_ML) $(PARSER_MLI): $(PARSER)
	$(OCAMLYACC) -v -b $(SRCDIR)/parser $<

$(SRCDIR)/main.cmx: $(SRCDIR)/main.ml $(PARSER_CMI) $(LEXER_ML)
	$(OCAMLOPT) $(FLAGS) -c -I $(SRCDIR) -o $@ $<

$(SRCDIR)/semantic.cmx: $(SRCDIR)/semantic.ml
	$(OCAMLOPT) $(FLAGS) -c -I $(SRCDIR) -o $@ $<

$(SRCDIR)/codegen.cmx: $(SRCDIR)/codegen.ml
	$(OCAMLOPT) $(FLAGS) -c -I $(SRCDIR) -o $@ $<

$(PARSER_CMI): $(PARSER_MLI)
	$(OCAMLOPT) $(FLAGS) -c -I $(SRCDIR) -o $@ $<

$(SRCDIR)/parser.cmx: $(PARSER_ML) $(PARSER_CMI)
	$(OCAMLOPT) $(FLAGS) -c -I $(SRCDIR) -o $@ $<

$(SRCDIR)/lexer.cmx: $(LEXER_ML) $(PARSER_CMI)
	$(OCAMLOPT) $(FLAGS) -c -I $(SRCDIR) -o $@ $<

clean:
	$(RM) $(SRCDIR)/*.cmx $(SRCDIR)/*.cmi $(SRCDIR)/*.o
	$(RM) $(LEXER_ML) $(PARSER_ML) $(PARSER_MLI)
	$(RM) $(SRCDIR)/parser.output

distclean: clean
	$(RM) $(EXECUTABLE)
