/* YACC parser for Java expressions, for GDB.
   Copyright (C) 1997.
   Free Software Foundation, Inc.

This file is part of GDB.

This program is free software; you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation; either version 2 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program; if not, write to the Free Software
Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA.  */

/* Parse a C expression from text in a string,
   and return the result as a  struct expression  pointer.
   That structure contains arithmetic operations in reverse polish,
   with constants represented by operations that are followed by special data.
   See expression.h for the details of the format.
   What is important here is that it can be built up sequentially
   during the process of parsing; the lower levels of the tree always
   come first in the result.

   Note that malloc's and realloc's in this file are transformed to
   xmalloc and xrealloc respectively by the same sed command in the
   makefile that remaps any other malloc/realloc inserted by the parser
   generator.  Doing this with #defines and trying to control the interaction
   with include files (<malloc.h> and <stdlib.h> for example) just became
   too messy, particularly when such includes can be inserted at random
   times by the parser generator.  */
  
%{

#include "defs.h"
#include "gdb_string.h"
#include <ctype.h>
#include "expression.h"
#include "value.h"
#include "parser-defs.h"
#include "language.h"
#include "java-lang.h"
#include "bfd.h" /* Required by objfiles.h.  */
#include "symfile.h" /* Required by objfiles.h.  */
#include "objfiles.h" /* For have_full_symbols and have_partial_symbols */

/* Remap normal yacc parser interface names (yyparse, yylex, yyerror, etc),
   as well as gratuitiously global symbol names, so we can have multiple
   yacc generated parsers in gdb.  Note that these are only the variables
   produced by yacc.  If other parser generators (bison, byacc, etc) produce
   additional global names that conflict at link time, then those parser
   generators need to be fixed instead of adding those names to this list. */

#define	yymaxdepth java_maxdepth
#define	yyparse	java_parse
#define	yylex	java_lex
#define	yyerror	java_error
#define	yylval	java_lval
#define	yychar	java_char
#define	yydebug	java_debug
#define	yypact	java_pact	
#define	yyr1	java_r1			
#define	yyr2	java_r2			
#define	yydef	java_def		
#define	yychk	java_chk		
#define	yypgo	java_pgo		
#define	yyact	java_act		
#define	yyexca	java_exca
#define yyerrflag java_errflag
#define yynerrs	java_nerrs
#define	yyps	java_ps
#define	yypv	java_pv
#define	yys	java_s
#define	yy_yys	java_yys
#define	yystate	java_state
#define	yytmp	java_tmp
#define	yyv	java_v
#define	yy_yyv	java_yyv
#define	yyval	java_val
#define	yylloc	java_lloc
#define yyreds	java_reds		/* With YYDEBUG defined */
#define yytoks	java_toks		/* With YYDEBUG defined */
#define yylhs	java_yylhs
#define yylen	java_yylen
#define yydefred java_yydefred
#define yydgoto	java_yydgoto
#define yysindex java_yysindex
#define yyrindex java_yyrindex
#define yygindex java_yygindex
#define yytable	 java_yytable
#define yycheck	 java_yycheck

#ifndef YYDEBUG
#define	YYDEBUG	0		/* Default to no yydebug support */
#endif

int
yyparse PARAMS ((void));

static int
yylex PARAMS ((void));

void
yyerror PARAMS ((char *));

static struct type * java_type_from_name PARAMS ((struct stoken));
static void push_variable PARAMS ((struct stoken));

%}

/* Although the yacc "value" of an expression is not used,
   since the result is stored in the structure being created,
   other node types do have values.  */

%union
  {
    LONGEST lval;
    struct {
      LONGEST val;
      struct type *type;
    } typed_val_int;
    struct {
      DOUBLEST dval;
      struct type *type;
    } typed_val_float;
    struct symbol *sym;
    struct type *tval;
    struct stoken sval;
    struct ttype tsym;
    struct symtoken ssym;
    struct block *bval;
    enum exp_opcode opcode;
    struct internalvar *ivar;
    int *ivec;
  }

%{
/* YYSTYPE gets defined by %union */
static int
parse_number PARAMS ((char *, int, int, YYSTYPE *));
%}

%type <lval> rcurly Dims Dims_opt
%type <tval> ClassOrInterfaceType ClassType /* ReferenceType Type ArrayType */
%type <tval> IntegralType FloatingPointType NumericType PrimitiveType

%token <typed_val_int> INTEGER_LITERAL
%token <typed_val_float> FLOATING_POINT_LITERAL

%token <sval> IDENTIFIER
%token <sval> STRING_LITERAL
%token <lval> BOOLEAN_LITERAL
%token <tsym> TYPENAME
%type <sval> Name SimpleName QualifiedName ForcedName

/* A NAME_OR_INT is a symbol which is not known in the symbol table,
   but which would parse as a valid number in the current input radix.
   E.g. "c" when input_radix==16.  Depending on the parse, it will be
   turned into a name or into a number.  */

%token <sval> NAME_OR_INT 

%token ERROR

/* Special type cases, put in to allow the parser to distinguish different
   legal basetypes.  */
%token LONG SHORT BYTE INT CHAR BOOLEAN DOUBLE FLOAT

%token VARIABLE

%token <opcode> ASSIGN_MODIFY

%token THIS SUPER NEW

%left ','
%right '=' ASSIGN_MODIFY
%right '?'
%left OROR
%left ANDAND
%left '|'
%left '^'
%left '&'
%left EQUAL NOTEQUAL
%left '<' '>' LEQ GEQ
%left LSH RSH
%left '+' '-'
%left '*' '/' '%'
%right INCREMENT DECREMENT
%right '.' '[' '('


%%

start   :	exp1
/*	|	type_exp FIXME */
	;

StringLiteral:
	STRING_LITERAL
		{
		  write_exp_elt_opcode (OP_STRING);
		  write_exp_string ($1);
		  write_exp_elt_opcode (OP_STRING);
		}
;

Literal	:
	INTEGER_LITERAL
		{ write_exp_elt_opcode (OP_LONG);
		  write_exp_elt_type ($1.type);
		  write_exp_elt_longcst ((LONGEST)($1.val));
		  write_exp_elt_opcode (OP_LONG); }
|	NAME_OR_INT
		{ YYSTYPE val;
		  parse_number ($1.ptr, $1.length, 0, &val);
		  write_exp_elt_opcode (OP_LONG);
		  write_exp_elt_type (val.typed_val_int.type);
		  write_exp_elt_longcst ((LONGEST)val.typed_val_int.val);
		  write_exp_elt_opcode (OP_LONG);
		}
|	FLOATING_POINT_LITERAL
		{ write_exp_elt_opcode (OP_DOUBLE);
		  write_exp_elt_type ($1.type);
		  write_exp_elt_dblcst ($1.dval);
		  write_exp_elt_opcode (OP_DOUBLE); }
|	BOOLEAN_LITERAL
		{ write_exp_elt_opcode (OP_LONG);
		  write_exp_elt_type (java_boolean_type);
		  write_exp_elt_longcst ((LONGEST)$1);
		  write_exp_elt_opcode (OP_LONG); }
|	StringLiteral
	;

/* UNUSED:
Type:
	PrimitiveType
|	ReferenceType
;
*/

PrimitiveType:
	NumericType
|	BOOLEAN
		{ $$ = java_boolean_type; }
;

NumericType:
	IntegralType
|	FloatingPointType
;

IntegralType:
	BYTE
		{ $$ = java_byte_type; }
|	SHORT
		{ $$ = java_short_type; }
|	INT
		{ $$ = java_int_type; }
|	LONG
		{ $$ = java_long_type; }
|	CHAR
		{ $$ = java_char_type; }
;

FloatingPointType:
	FLOAT
		{ $$ = java_float_type; }
|	DOUBLE
		{ $$ = java_double_type; }
;

/* UNUSED:
ReferenceType:
	ClassOrInterfaceType
|	ArrayType
;
*/

ClassOrInterfaceType:
	Name
		{ $$ = java_type_from_name ($1); }
;

ClassType:
	ClassOrInterfaceType
;

/* UNUSED:
ArrayType:
	PrimitiveType Dims
		{ $$ = java_array_type ($1, $2); }
|	Name Dims
		{ $$ = java_array_type (java_type_from_name ($1), $2); }
;
*/

Name:
	IDENTIFIER
|	QualifiedName
;

ForcedName:
	SimpleName
|	QualifiedName
;

SimpleName:
	IDENTIFIER
|	NAME_OR_INT
;

QualifiedName:
	Name '.' SimpleName
		{ $$.length = $1.length + $3.length + 1;
		  if ($1.ptr + $1.length + 1 == $3.ptr
		      && $1.ptr[$1.length] == '.')
		    $$.ptr = $1.ptr;  /* Optimization. */
		  else
		    {
		      $$.ptr = (char *) malloc ($$.length + 1);
		      make_cleanup (free, $$.ptr);
		      sprintf ($$.ptr, "%.*s.%.*s",
			       $1.length, $1.ptr, $3.length, $3.ptr);
		} }
;

/*
type_exp:	type
			{ write_exp_elt_opcode(OP_TYPE);
			  write_exp_elt_type($1);
			  write_exp_elt_opcode(OP_TYPE);}
	;
	*/

/* Expressions, including the comma operator.  */
exp1	:	Expression
	|	exp1 ',' Expression
			{ write_exp_elt_opcode (BINOP_COMMA); }
	;

Primary:
	PrimaryNoNewArray
|	ArrayCreationExpression
;

PrimaryNoNewArray:
	Literal
|	THIS
		{ write_exp_elt_opcode (OP_THIS);
		  write_exp_elt_opcode (OP_THIS); }
|	'(' Expression ')'
|	ClassInstanceCreationExpression
|	FieldAccess
|	MethodInvocation
|	ArrayAccess
|	lcurly ArgumentList rcurly
		{ write_exp_elt_opcode (OP_ARRAY);
		  write_exp_elt_longcst ((LONGEST) 0);
		  write_exp_elt_longcst ((LONGEST) $3);
		  write_exp_elt_opcode (OP_ARRAY); }
;

lcurly:
	'{'
		{ start_arglist (); }
;

rcurly:
	'}'
		{ $$ = end_arglist () - 1; }
;

ClassInstanceCreationExpression:
	NEW ClassType '(' ArgumentList_opt ')'
		{ error ("FIXME - ClassInstanceCreationExpression"); }
;

ArgumentList:
	Expression
		{ arglist_len = 1; }
|	ArgumentList ',' Expression
		{ arglist_len++; }
;

ArgumentList_opt:
	/* EMPTY */
		{ arglist_len = 0; }
| ArgumentList
;

ArrayCreationExpression:
	NEW PrimitiveType DimExprs Dims_opt
		{ error ("FIXME - ArrayCreatiionExpression"); }
|	NEW ClassOrInterfaceType DimExprs Dims_opt
		{ error ("FIXME - ArrayCreatiionExpression"); }
;

DimExprs:
	DimExpr
|	DimExprs DimExpr
;

DimExpr:
	'[' Expression ']'
;

Dims:
	'[' ']'
		{ $$ = 1; }
|	Dims '[' ']'
	{ $$ = $1 + 1; }
;

Dims_opt:
	Dims
|	/* EMPTY */
		{ $$ = 0; }
;

FieldAccess:
	Primary '.' SimpleName
		{ write_exp_elt_opcode (STRUCTOP_STRUCT);
		  write_exp_string ($3);
		  write_exp_elt_opcode (STRUCTOP_STRUCT); }
/*|	SUPER '.' SimpleName { FIXME } */
;

MethodInvocation:
	Name '(' ArgumentList_opt ')'
		{ error ("method invocation not implemented"); }
|	Primary '.' SimpleName '(' ArgumentList_opt ')'
		{ error ("method invocation not implemented"); }
|	SUPER '.' SimpleName '(' ArgumentList_opt ')'
		{ error ("method invocation not implemented"); }
;

ArrayAccess:
	Name '[' Expression ']'
		{ error ("ArrayAccess"); } /* FIXME - NASTY */
|	PrimaryNoNewArray '[' Expression ']'
		{ write_exp_elt_opcode (BINOP_SUBSCRIPT); }
;

PostfixExpression:
	Primary
|	Name
		{ push_variable ($1); }
|	VARIABLE
		/* Already written by write_dollar_variable. */
|	PostIncrementExpression
|	PostDecrementExpression
;

PostIncrementExpression:
	PostfixExpression INCREMENT
		{ write_exp_elt_opcode (UNOP_POSTINCREMENT); }
;

PostDecrementExpression:
	PostfixExpression DECREMENT
		{ write_exp_elt_opcode (UNOP_POSTDECREMENT); }
;

UnaryExpression:
	PreIncrementExpression
|	PreDecrementExpression
|	'+' UnaryExpression
|	'-' UnaryExpression
		{ write_exp_elt_opcode (UNOP_NEG); }
|	'*' UnaryExpression 
		{ write_exp_elt_opcode (UNOP_IND); } /*FIXME not in Java  */
|	UnaryExpressionNotPlusMinus
;

PreIncrementExpression:
	INCREMENT UnaryExpression
		{ write_exp_elt_opcode (UNOP_PREINCREMENT); }
;

PreDecrementExpression:
	DECREMENT UnaryExpression
		{ write_exp_elt_opcode (UNOP_PREDECREMENT); }
;

UnaryExpressionNotPlusMinus:
	PostfixExpression
|	'~' UnaryExpression
		{ write_exp_elt_opcode (UNOP_COMPLEMENT); }
|	'!' UnaryExpression
		{ write_exp_elt_opcode (UNOP_LOGICAL_NOT); }
|	CastExpression
	;

CastExpression:
	'(' PrimitiveType Dims_opt ')' UnaryExpression
		{ write_exp_elt_opcode (UNOP_CAST);
		  write_exp_elt_type (java_array_type ($2, $3));
		  write_exp_elt_opcode (UNOP_CAST); }
|	'(' Expression ')' UnaryExpressionNotPlusMinus /* FIXME */
|	'(' Name Dims ')' UnaryExpressionNotPlusMinus
		{ write_exp_elt_opcode (UNOP_CAST);
		  write_exp_elt_type (java_array_type (java_type_from_name ($2), $3));
		  write_exp_elt_opcode (UNOP_CAST); }
;


MultiplicativeExpression:
	UnaryExpression
|	MultiplicativeExpression '*' UnaryExpression
		{ write_exp_elt_opcode (BINOP_MUL); }
|	MultiplicativeExpression '/' UnaryExpression
		{ write_exp_elt_opcode (BINOP_DIV); }
|	MultiplicativeExpression '%' UnaryExpression
		{ write_exp_elt_opcode (BINOP_REM); }
;

AdditiveExpression:
	MultiplicativeExpression
|	AdditiveExpression '+' MultiplicativeExpression
		{ write_exp_elt_opcode (BINOP_ADD); }
|	AdditiveExpression '-' MultiplicativeExpression
		{ write_exp_elt_opcode (BINOP_SUB); }
;

ShiftExpression:
	AdditiveExpression
|	ShiftExpression LSH AdditiveExpression
		{ write_exp_elt_opcode (BINOP_LSH); }
|	ShiftExpression RSH AdditiveExpression
		{ write_exp_elt_opcode (BINOP_RSH); }
/* |	ShiftExpression >>> AdditiveExpression { FIXME } */
;

RelationalExpression:
	ShiftExpression
|	RelationalExpression '<' ShiftExpression
		{ write_exp_elt_opcode (BINOP_LESS); }
|	RelationalExpression '>' ShiftExpression
		{ write_exp_elt_opcode (BINOP_GTR); }
|	RelationalExpression LEQ ShiftExpression
		{ write_exp_elt_opcode (BINOP_LEQ); }
|	RelationalExpression GEQ ShiftExpression
		{ write_exp_elt_opcode (BINOP_GEQ); }
/* | RelationalExpresion INSTANCEOF ReferenceType { FIXME } */
;

EqualityExpression:
	RelationalExpression
|	EqualityExpression EQUAL RelationalExpression
		{ write_exp_elt_opcode (BINOP_EQUAL); }
|	EqualityExpression NOTEQUAL RelationalExpression
		{ write_exp_elt_opcode (BINOP_NOTEQUAL); }
;

AndExpression:
	EqualityExpression
|	AndExpression '&' EqualityExpression
		{ write_exp_elt_opcode (BINOP_BITWISE_AND); }
;

ExclusiveOrExpression:
	AndExpression
|	ExclusiveOrExpression '^' AndExpression
		{ write_exp_elt_opcode (BINOP_BITWISE_XOR); }
;
InclusiveOrExpression:
	ExclusiveOrExpression
|	InclusiveOrExpression '|' ExclusiveOrExpression
		{ write_exp_elt_opcode (BINOP_BITWISE_IOR); }
;

ConditionalAndExpression:
	InclusiveOrExpression
|	ConditionalAndExpression ANDAND InclusiveOrExpression
		{ write_exp_elt_opcode (BINOP_LOGICAL_AND); }
;

ConditionalOrExpression:
	ConditionalAndExpression
|	ConditionalOrExpression OROR ConditionalAndExpression
		{ write_exp_elt_opcode (BINOP_LOGICAL_OR); }
;

ConditionalExpression:
	ConditionalOrExpression
|	ConditionalOrExpression '?' Expression ':' ConditionalExpression
		{ write_exp_elt_opcode (TERNOP_COND); }
;

AssignmentExpression:
	ConditionalExpression
|	Assignment
;
			  
Assignment:
	LeftHandSide '=' ConditionalExpression
		{ write_exp_elt_opcode (BINOP_ASSIGN); }
|	LeftHandSide ASSIGN_MODIFY ConditionalExpression
		{ write_exp_elt_opcode (BINOP_ASSIGN_MODIFY);
		  write_exp_elt_opcode ($2);
		  write_exp_elt_opcode (BINOP_ASSIGN_MODIFY); }
;

LeftHandSide:
	ForcedName
		{ push_variable ($1); }
|	VARIABLE
		/* Already written by write_dollar_variable. */
|	FieldAccess
|	ArrayAccess
;


Expression:
	AssignmentExpression
;

%%
/* Take care of parsing a number (anything that starts with a digit).
   Set yylval and return the token type; update lexptr.
   LEN is the number of characters in it.  */

/*** Needs some error checking for the float case ***/

static int
parse_number (p, len, parsed_float, putithere)
     register char *p;
     register int len;
     int parsed_float;
     YYSTYPE *putithere;
{
  register ULONGEST n = 0;
  ULONGEST limit, limit_div_base;

  register int c;
  register int base = input_radix;
  int unsigned_p = 0;

  struct type *type;

  if (parsed_float)
    {
      /* It's a float since it contains a point or an exponent.  */

      if (sizeof (putithere->typed_val_float.dval) <= sizeof (float))
	sscanf (p, "%g", &putithere->typed_val_float.dval);
      else if (sizeof (putithere->typed_val_float.dval) <= sizeof (double))
	sscanf (p, "%lg", &putithere->typed_val_float.dval);
      else
	{
#ifdef PRINTF_HAS_LONG_DOUBLE
	  sscanf (p, "%Lg", &putithere->typed_val_float.dval);
#else
	  /* Scan it into a double, then assign it to the long double.
	     This at least wins with values representable in the range
	     of doubles. */
	  double temp;
	  sscanf (p, "%lg", &temp);
	  putithere->typed_val_float.dval = temp;
#endif
	}

      /* See if it has `f' or `d' suffix (float or double).  */

      c = tolower (p[len - 1]);

      if (c == 'f' || c == 'F')
	putithere->typed_val_float.type = builtin_type_float;
      else if (isdigit (c) || c == '.' || c == 'd' || c == 'D')
	putithere->typed_val_float.type = builtin_type_double;
      else
	return ERROR;

      return FLOATING_POINT_LITERAL;
}

  /* Handle base-switching prefixes 0x, 0t, 0d, 0 */
  if (p[0] == '0')
    switch (p[1])
      {
      case 'x':
      case 'X':
	if (len >= 3)
	  {
	    p += 2;
	    base = 16;
	    len -= 2;
	  }
	break;

      case 't':
      case 'T':
      case 'd':
      case 'D':
	if (len >= 3)
	  {
	    p += 2;
	    base = 10;
	    len -= 2;
	  }
	break;

      default:
	base = 8;
	break;
      }

  c = p[len-1];
  limit = (ULONGEST)0xffffffff;
  if (c == 'l' || c == 'L')
    {
      type = java_long_type;
      len--;
      /* A paranoid calculation of (1<<64)-1. */
      limit = ((limit << 16) << 16) | limit;
    }
  else
    {
      type = java_int_type;
    }
  limit_div_base = limit / (ULONGEST) base;

  while (--len >= 0)
    {
      c = *p++;
      if (c >= '0' && c <= '9')
	c -= '0';
      else
	{
	  if (c >= 'A' && c <= 'Z')
	    c += 'a' - 'A';
	  if (c >= 'a' && c - 'a' + 10 < base)
	    c -= 'a' + 10;
	  else
	    return ERROR;	/* Char not a digit */
	}
      if (c >= base)
	return ERROR;
      if (n > limit_div_base
	  || (n *= base) > limit - c)
	error ("Numeric constant too large.");
      n += c;
	}

   putithere->typed_val_int.val = n;
   putithere->typed_val_int.type = type;
   return INTEGER_LITERAL;
}

struct token
{
  char *operator;
  int token;
  enum exp_opcode opcode;
};

static const struct token tokentab3[] =
  {
    {">>=", ASSIGN_MODIFY, BINOP_RSH},
    {"<<=", ASSIGN_MODIFY, BINOP_LSH}
  };

static const struct token tokentab2[] =
  {
    {"+=", ASSIGN_MODIFY, BINOP_ADD},
    {"-=", ASSIGN_MODIFY, BINOP_SUB},
    {"*=", ASSIGN_MODIFY, BINOP_MUL},
    {"/=", ASSIGN_MODIFY, BINOP_DIV},
    {"%=", ASSIGN_MODIFY, BINOP_REM},
    {"|=", ASSIGN_MODIFY, BINOP_BITWISE_IOR},
    {"&=", ASSIGN_MODIFY, BINOP_BITWISE_AND},
    {"^=", ASSIGN_MODIFY, BINOP_BITWISE_XOR},
    {"++", INCREMENT, BINOP_END},
    {"--", DECREMENT, BINOP_END},
    {"&&", ANDAND, BINOP_END},
    {"||", OROR, BINOP_END},
    {"<<", LSH, BINOP_END},
    {">>", RSH, BINOP_END},
    {"==", EQUAL, BINOP_END},
    {"!=", NOTEQUAL, BINOP_END},
    {"<=", LEQ, BINOP_END},
    {">=", GEQ, BINOP_END}
  };

/* Read one token, getting characters through lexptr.  */

static int
yylex ()
{
  int c;
  int namelen;
  unsigned int i;
  char *tokstart;
  char *tokptr;
  int tempbufindex;
  static char *tempbuf;
  static int tempbufsize;
  
 retry:

  tokstart = lexptr;
  /* See if it is a special token of length 3.  */
  for (i = 0; i < sizeof tokentab3 / sizeof tokentab3[0]; i++)
    if (STREQN (tokstart, tokentab3[i].operator, 3))
      {
	lexptr += 3;
	yylval.opcode = tokentab3[i].opcode;
	return tokentab3[i].token;
      }

  /* See if it is a special token of length 2.  */
  for (i = 0; i < sizeof tokentab2 / sizeof tokentab2[0]; i++)
    if (STREQN (tokstart, tokentab2[i].operator, 2))
      {
	lexptr += 2;
	yylval.opcode = tokentab2[i].opcode;
	return tokentab2[i].token;
      }

  switch (c = *tokstart)
    {
    case 0:
      return 0;

    case ' ':
    case '\t':
    case '\n':
      lexptr++;
      goto retry;

    case '\'':
      /* We either have a character constant ('0' or '\177' for example)
	 or we have a quoted symbol reference ('foo(int,int)' in C++
	 for example). */
      lexptr++;
      c = *lexptr++;
      if (c == '\\')
	c = parse_escape (&lexptr);
      else if (c == '\'')
	error ("Empty character constant.");

      yylval.typed_val_int.val = c;
      yylval.typed_val_int.type = builtin_type_char;

      c = *lexptr++;
      if (c != '\'')
	{
	  namelen = skip_quoted (tokstart) - tokstart;
	  if (namelen > 2)
	    {
	      lexptr = tokstart + namelen;
	      if (lexptr[-1] != '\'')
		error ("Unmatched single quote.");
	      namelen -= 2;
	      tokstart++;
	      goto tryname;
	    }
	  error ("Invalid character constant.");
	}
      return INTEGER_LITERAL;

    case '(':
      paren_depth++;
      lexptr++;
      return c;

    case ')':
      if (paren_depth == 0)
	return 0;
      paren_depth--;
      lexptr++;
      return c;

    case ',':
      if (comma_terminates && paren_depth == 0)
	return 0;
      lexptr++;
      return c;

    case '.':
      /* Might be a floating point number.  */
      if (lexptr[1] < '0' || lexptr[1] > '9')
	goto symbol;		/* Nope, must be a symbol. */
      /* FALL THRU into number case.  */

    case '0':
    case '1':
    case '2':
    case '3':
    case '4':
    case '5':
    case '6':
    case '7':
    case '8':
    case '9':
      {
	/* It's a number.  */
	int got_dot = 0, got_e = 0, toktype;
	register char *p = tokstart;
	int hex = input_radix > 10;

	if (c == '0' && (p[1] == 'x' || p[1] == 'X'))
	  {
	    p += 2;
	    hex = 1;
	  }
	else if (c == '0' && (p[1]=='t' || p[1]=='T' || p[1]=='d' || p[1]=='D'))
	  {
	    p += 2;
	    hex = 0;
	  }

	for (;; ++p)
	  {
	    /* This test includes !hex because 'e' is a valid hex digit
	       and thus does not indicate a floating point number when
	       the radix is hex.  */
	    if (!hex && !got_e && (*p == 'e' || *p == 'E'))
	      got_dot = got_e = 1;
	    /* This test does not include !hex, because a '.' always indicates
	       a decimal floating point number regardless of the radix.  */
	    else if (!got_dot && *p == '.')
	      got_dot = 1;
	    else if (got_e && (p[-1] == 'e' || p[-1] == 'E')
		     && (*p == '-' || *p == '+'))
	      /* This is the sign of the exponent, not the end of the
		 number.  */
	      continue;
	    /* We will take any letters or digits.  parse_number will
	       complain if past the radix, or if L or U are not final.  */
	    else if ((*p < '0' || *p > '9')
		     && ((*p < 'a' || *p > 'z')
				  && (*p < 'A' || *p > 'Z')))
	      break;
	  }
	toktype = parse_number (tokstart, p - tokstart, got_dot|got_e, &yylval);
        if (toktype == ERROR)
	  {
	    char *err_copy = (char *) alloca (p - tokstart + 1);

	    memcpy (err_copy, tokstart, p - tokstart);
	    err_copy[p - tokstart] = 0;
	    error ("Invalid number \"%s\".", err_copy);
	  }
	lexptr = p;
	return toktype;
      }

    case '+':
    case '-':
    case '*':
    case '/':
    case '%':
    case '|':
    case '&':
    case '^':
    case '~':
    case '!':
    case '<':
    case '>':
    case '[':
    case ']':
    case '?':
    case ':':
    case '=':
    case '{':
    case '}':
    symbol:
      lexptr++;
      return c;

    case '"':

      /* Build the gdb internal form of the input string in tempbuf,
	 translating any standard C escape forms seen.  Note that the
	 buffer is null byte terminated *only* for the convenience of
	 debugging gdb itself and printing the buffer contents when
	 the buffer contains no embedded nulls.  Gdb does not depend
	 upon the buffer being null byte terminated, it uses the length
	 string instead.  This allows gdb to handle C strings (as well
	 as strings in other languages) with embedded null bytes */

      tokptr = ++tokstart;
      tempbufindex = 0;

      do {
	/* Grow the static temp buffer if necessary, including allocating
	   the first one on demand. */
	if (tempbufindex + 1 >= tempbufsize)
	  {
	    tempbuf = (char *) realloc (tempbuf, tempbufsize += 64);
	  }
	switch (*tokptr)
	  {
	  case '\0':
	  case '"':
	    /* Do nothing, loop will terminate. */
	    break;
	  case '\\':
	    tokptr++;
	    c = parse_escape (&tokptr);
	    if (c == -1)
	      {
		continue;
	      }
	    tempbuf[tempbufindex++] = c;
	    break;
	  default:
	    tempbuf[tempbufindex++] = *tokptr++;
	    break;
	  }
      } while ((*tokptr != '"') && (*tokptr != '\0'));
      if (*tokptr++ != '"')
	{
	  error ("Unterminated string in expression.");
	}
      tempbuf[tempbufindex] = '\0';	/* See note above */
      yylval.sval.ptr = tempbuf;
      yylval.sval.length = tempbufindex;
      lexptr = tokptr;
      return (STRING_LITERAL);
    }

  if (!(c == '_' || c == '$'
	|| (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z')))
    /* We must have come across a bad character (e.g. ';').  */
    error ("Invalid character '%c' in expression.", c);

  /* It's a name.  See how long it is.  */
  namelen = 0;
  for (c = tokstart[namelen];
       (c == '_' || c == '$' || (c >= '0' && c <= '9')
	|| (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || c == '<');)
    {
       if (c == '<')
	 {
	   int i = namelen;
	   while (tokstart[++i] && tokstart[i] != '>');
	   if (tokstart[i] == '>')
	     namelen = i;
	  }
       c = tokstart[++namelen];
     }

  /* The token "if" terminates the expression and is NOT 
     removed from the input stream.  */
  if (namelen == 2 && tokstart[0] == 'i' && tokstart[1] == 'f')
    {
      return 0;
    }

  lexptr += namelen;

  tryname:

  /* Catch specific keywords.  Should be done with a data structure.  */
  switch (namelen)
    {
    case 7:
      if (STREQN (tokstart, "boolean", 7))
	return BOOLEAN;
      break;
    case 6:
      if (STREQN (tokstart, "double", 6))      
	return DOUBLE;
      break;
    case 5:
      if (STREQN (tokstart, "short", 5))
	return SHORT;
      if (STREQN (tokstart, "false", 5))
	{
	  yylval.lval = 0;
	  return BOOLEAN_LITERAL;
	}
      if (STREQN (tokstart, "super", 5))
	return SUPER;
      if (STREQN (tokstart, "float", 5))
	return FLOAT;
      break;
    case 4:
      if (STREQN (tokstart, "long", 4))
	return LONG;
      if (STREQN (tokstart, "byte", 4))
	return BYTE;
      if (STREQN (tokstart, "char", 4))
	return CHAR;
      if (STREQN (tokstart, "true", 4))
	{
	  yylval.lval = 1;
	  return BOOLEAN_LITERAL;
	}
      if (current_language->la_language == language_cplus
	  && STREQN (tokstart, "this", 4))
	{
	  static const char this_name[] =
				 { CPLUS_MARKER, 't', 'h', 'i', 's', '\0' };

	  if (lookup_symbol (this_name, expression_context_block,
			     VAR_NAMESPACE, (int *) NULL,
			     (struct symtab **) NULL))
	    return THIS;
	}
      break;
    case 3:
      if (STREQN (tokstart, "int", 3))
	return INT;
      if (STREQN (tokstart, "new", 3))
	return NEW;
      break;
    default:
      break;
    }

  yylval.sval.ptr = tokstart;
  yylval.sval.length = namelen;

  if (*tokstart == '$')
    {
      write_dollar_variable (yylval.sval);
      return VARIABLE;
    }

  /* Input names that aren't symbols but ARE valid hex numbers,
     when the input radix permits them, can be names or numbers
     depending on the parse.  Note we support radixes > 16 here.  */
  if (((tokstart[0] >= 'a' && tokstart[0] < 'a' + input_radix - 10) ||
       (tokstart[0] >= 'A' && tokstart[0] < 'A' + input_radix - 10)))
    {
      YYSTYPE newlval;	/* Its value is ignored.  */
      int hextype = parse_number (tokstart, namelen, 0, &newlval);
      if (hextype == INTEGER_LITERAL)
	return NAME_OR_INT;
    }
  return IDENTIFIER;
}

void
yyerror (msg)
     char *msg;
{
  error ("A %s in expression, near `%s'.", (msg ? msg : "error"), lexptr);
}

static struct type *
java_type_from_name (name)
     struct stoken name;
 
{
  char *tmp = copy_name (name);
  struct type *typ = java_lookup_class (tmp);
  if (typ == NULL || TYPE_CODE (typ) != TYPE_CODE_STRUCT)
    error ("No class named %s.", tmp);
  return typ;
}

static void
push_variable (name)
     struct stoken name;
 
{
  char *tmp = copy_name (name);
  int is_a_field_of_this = 0;
  struct symbol *sym;
  struct type *typ;
  sym = lookup_symbol (tmp, expression_context_block, VAR_NAMESPACE,
		       &is_a_field_of_this, (struct symtab **) NULL);
  if (sym)
    {
      if (symbol_read_needs_frame (sym))
	{
	  if (innermost_block == 0 ||
	      contained_in (block_found, innermost_block))
	    innermost_block = block_found;
	}

      write_exp_elt_opcode (OP_VAR_VALUE);
      /* We want to use the selected frame, not another more inner frame
	 which happens to be in the same block.  */
      write_exp_elt_block (NULL);
      write_exp_elt_sym (sym);
      write_exp_elt_opcode (OP_VAR_VALUE);
      return;
    }
  if (is_a_field_of_this)
    {
      /* it hangs off of `this'.  Must not inadvertently convert from a
	 method call to data ref.  */
      if (innermost_block == 0 || 
	  contained_in (block_found, innermost_block))
	innermost_block = block_found;
      write_exp_elt_opcode (OP_THIS);
      write_exp_elt_opcode (OP_THIS);
      write_exp_elt_opcode (STRUCTOP_PTR);
      write_exp_string (name);
      write_exp_elt_opcode (STRUCTOP_PTR);
      return;
    }

  typ = java_lookup_class (tmp);
  if (typ != NULL)
    {
      write_exp_elt_opcode(OP_TYPE);
      write_exp_elt_type(typ);
      write_exp_elt_opcode(OP_TYPE);
    }
  else
    {
      struct minimal_symbol *msymbol;

      msymbol = lookup_minimal_symbol (tmp, NULL, NULL);
      if (msymbol != NULL)
	{
	  write_exp_msymbol (msymbol,
			     lookup_function_type (builtin_type_int),
			     builtin_type_int);
	}
      else if (!have_full_symbols () && !have_partial_symbols ())
	error ("No symbol table is loaded.  Use the \"file\" command.");
      else
	error ("No symbol \"%s\" in current context.", tmp);
    }

}
