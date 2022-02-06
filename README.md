# Tiny Cell Evaluator

Currently it supports:

* Loading `|` limited text
* `sep=` magic line as first line of CSV file 
* Pretty printing of tables
* `A1` style references inside cells
* Circular-dependency detection
* Basic math ops (+, -, /, *)

## Tasks and ideas

+ Cell cloning
    - tsoding `:<^>V` syntax -> maybe translate it into formulas
        `:>` -> `=COPYFROM('LEFT')` - copy left, evaluated cell
+ Relative and absolute addressing
+ Named columns and rows, cells, regions 
    ability to define name for range of cells
    basis would be just taking first row and first column and named indexes, than can be used interchangably with `A1` notation
+ Formula evaluation
    - Math formulas
    - Higher-order formulas `=SUM(FILTER([dogAge], >10))`
    - Array-like and iterator-like formulas
+ Optimization to formula/cell evaluator
+ Primitive GUI