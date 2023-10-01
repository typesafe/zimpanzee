Learning Zig by implementing an interpreter for the Monkey language.

### Tokens

- eof
- comment (string)
- illegal (char)
- identifier(string)
- integer(string)
- operator (Operator)
- keyword (Keyword)
- semicolon
- dot,
- lbrace
- rbrace
- lparen
- rparen
- lbracket
- rbracket

### Keyword

- let
- ret
- if
- else
- fn

### Operator

- bang
- asterisk
- fslash
- assign
- plus
- minus
- lt
- gt
- eq
- ne

### Nodes

- statement
  - let
  - return
  - if
- expression
  - identifier Identifier{ token, name }
  - literal Literal{ token, name }
  - op Op{ token, left, right}
