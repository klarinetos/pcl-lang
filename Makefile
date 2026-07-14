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
SOURCES = $(SRCDIR)/main.ml $(SRCDIR)/symtab.ml $(SRCDIR)/semantic.ml $(SRCDIR)/codegen.ml

# Generated files
LEXER_ML = $(SRCDIR)/lexer.ml
PARSER_ML = $(SRCDIR)/parser.ml
PARSER_MLI = $(SRCDIR)/parser.mli

# Object files
OBJS = $(SRCDIR)/ast.cmx $(SRCDIR)/parser.cmx $(SRCDIR)/lexer.cmx $(SRCDIR)/symtab.cmx $(SRCDIR)/semantic.cmx $(SRCDIR)/codegen.cmx $(SRCDIR)/main.cmx
INTERP_OBJS = $(SRCDIR)/ast.cmx $(SRCDIR)/parser.cmx $(SRCDIR)/lexer.cmx $(SRCDIR)/symtab.cmx $(SRCDIR)/semantic.cmx $(SRCDIR)/interp.cmx $(SRCDIR)/interp_main.cmx
PARSER_CMI = $(SRCDIR)/parser.cmi
AST_CMI = $(SRCDIR)/ast.cmi

# Executables
EXECUTABLE = pclc
INTERP_EXECUTABLE = pcli

.PHONY: all clean distclean

all: $(EXECUTABLE) $(INTERP_EXECUTABLE)

$(EXECUTABLE): $(LEXER_ML) $(PARSER_ML) $(OBJS)
	$(OCAMLOPT) $(FLAGS) -o $@ $(OBJS)

$(INTERP_EXECUTABLE): $(LEXER_ML) $(PARSER_ML) $(INTERP_OBJS)
	$(OCAMLOPT) $(FLAGS) -o $@ $(INTERP_OBJS)

$(LEXER_ML): $(LEXER) $(PARSER_MLI)
	$(OCAMLLEX) -o $@ $<

$(PARSER_ML) $(PARSER_MLI): $(PARSER)
	$(OCAMLYACC) -v -b $(SRCDIR)/parser $<

$(SRCDIR)/main.cmx: $(SRCDIR)/main.ml $(PARSER_CMI) $(AST_CMI) $(LEXER_ML) $(SRCDIR)/semantic.cmx
	$(OCAMLOPT) $(FLAGS) -c -I $(SRCDIR) -o $@ $<

$(SRCDIR)/symtab.cmx: $(SRCDIR)/symtab.ml $(AST_CMI)
	$(OCAMLOPT) $(FLAGS) -c -I $(SRCDIR) -o $@ $<

$(SRCDIR)/semantic.cmx: $(SRCDIR)/semantic.ml $(SRCDIR)/symtab.cmx $(AST_CMI)
	$(OCAMLOPT) $(FLAGS) -c -I $(SRCDIR) -o $@ $<

$(SRCDIR)/codegen.cmx: $(SRCDIR)/codegen.ml
	$(OCAMLOPT) $(FLAGS) -c -I $(SRCDIR) -o $@ $<

$(AST_CMI) $(SRCDIR)/ast.cmx: $(SRCDIR)/ast.ml
	$(OCAMLOPT) $(FLAGS) -c -I $(SRCDIR) -o $(SRCDIR)/ast.cmx $<

$(PARSER_CMI): $(PARSER_MLI) $(AST_CMI)
	$(OCAMLOPT) $(FLAGS) -c -I $(SRCDIR) -o $@ $<

$(SRCDIR)/parser.cmx: $(PARSER_ML) $(PARSER_CMI)
	$(OCAMLOPT) $(FLAGS) -c -I $(SRCDIR) -o $@ $<

$(SRCDIR)/lexer.cmx: $(LEXER_ML) $(PARSER_CMI)
	$(OCAMLOPT) $(FLAGS) -c -I $(SRCDIR) -o $@ $<

$(SRCDIR)/interp.cmx: $(SRCDIR)/interp.ml $(AST_CMI)
	$(OCAMLOPT) $(FLAGS) -c -I $(SRCDIR) -o $@ $<

$(SRCDIR)/interp_main.cmx: $(SRCDIR)/interp_main.ml $(SRCDIR)/interp.cmx $(SRCDIR)/semantic.cmx $(PARSER_CMI) $(LEXER_ML)
	$(OCAMLOPT) $(FLAGS) -c -I $(SRCDIR) -o $@ $<

clean:
	$(RM) $(SRCDIR)/*.cmx $(SRCDIR)/*.cmi $(SRCDIR)/*.o
	$(RM) $(LEXER_ML) $(PARSER_ML) $(PARSER_MLI)
	$(RM) $(SRCDIR)/parser.output

distclean: clean
	$(RM) $(EXECUTABLE) $(INTERP_EXECUTABLE)
