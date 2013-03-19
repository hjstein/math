

;;;; 0. Parser ;;;;
;;
;; The parser uses a top-down operator precedence (TDOP) parsing
;; methodology. For background see the following:
;;
;; http://javascript.crockford.com/tdop/tdop.html
;; http://effbot.org/zone/simple-top-down-parsing.htm
;; http://journal.stuffwithstuff.com/2011/03/19/pratt-parsers-expression-parsing-made-easy/
;; http://eli.thegreenplace.net/2010/01/02/top-down-operator-precedence-parsing/
;;
;;;; 1. Terminology ;;;;
;;
;; Consider the following simple expression grammar.
;;
;; expr := number                 // a literal number
;; expr := '+' expr               // '+' is a prefix operator
;; expr := '(' expr ')'           // '(' and ')' are matchfix operators
;; expr := expr '++'              // '++' is a postfix operator
;; expr := expr '+' expr          // '+' is an infix operator
;;
;; TDOP divides the operators in the above operators into three
;; catergories: null denotation, left expression denotation and
;; `closer'. In much of the literature, the denotation terms are
;; abbreviated as `nud' and `led' respectively.
;;
;; The prefix '+' and the matchfix '(' are considered null denominator
;; operators because there is no 'left hand side' for the operator in
;; that context.
;;
;; The postfix '++' and infix '+' are considered left expression
;; denotation operators because there is a 'left hand side' to which
;; the operator applies.
;;
;; Even thought the matchfix ')' has an expression on the left, it is
;; considered a closer since it follows the last non-terminal in the production.
;;
;; Only the `nud' and `led' operators have associated parse function
;; that are displatched when they are read as tokens. The `closer'
;; operators are simply required to be read at the correct time but do
;; not have any associated parse function.
;;
;; Sometimes `ned' and `led' are refered to as prefix and infix, but that
;; is really a misnomer and can lead to confusion. The terms prefix,
;; infix and postfix describe a different dimension about an operator
;; than the terms null denonation and left expression denotation.
;;
;; The other important TDOP term is binding power which is related to
;; the precedence and associativity of an operator. Each operator has
;; both a left binding power and a right binding power. 
;;
;; The left binding power is how strongly the operator binds to the
;; preceeding term and the right binding power is how strongly the
;; operator binds to the succeeding term. The binding power is used to
;; control both operator precedence and associativity.
;; 
;;;; 2. Algorithm ;;;;
;;
;; The following pseudo-code describes the basic parsing
;; algorithm.
;;
;; parse-expression (right-binding-power = 0)
;;     Read `token'
;;     expression = Result of the `nud' parse method for `token' (nud token)
;;     while right-binding-power < left-binding-power(next token)
;;         Read `token'
;;         expression = Result of the `led' parse method for `token' (led expression token)
;;     return expression
;;
;; For each token read, either the `nud' or `led' parse method is
;; dispatched. Let's consider this in the context of the simple
;; grammar from above.
;;
;; The nud for number just returns the number.
;; The nud for the prefix '+' calls parse expression to get it's right expression.
;; The nud for '(' calls parse expression and then expects the closer ')'.
;; The led for postfix '++' simply applies its operation to the left expression.
;; The led for infix '+' calls parse expression to get its right expression.
;;


(require 'math-parse-util)
(require 'math-token)

(defconst math--tok nil
  "The current parser token.")

(defconst math--next-tok nil
  "The next parser token.")

(defun math-parse-error (msg token)
  "Dispatch an error for token with the given message."
  (error "%s:%d: error: %s" 
	 (math-token-file token)
	 (math-token-line token)
	 msg))

;; The core parsing methods.
;;
(defun math-parse-init ()
  (setq math--tok nil)
  (setq math--next-tok nil)
  (math-parse-advance-token))

(defun math-parse-advance-token ()
  "Get the next token and set its properties based on the parser tables."
  (let* ((token (math-tok-next-token))
	 (id (math-token-id token)))
    (math-token-set-nud-left-bp token (math-get-table id math-nud-left-bp-table))
    (math-token-set-nud-fn token (math-get-table id math-nud-fn-table))
    (math-token-set-led-left-bp token (math-get-table id math-led-left-bp-table))
    (math-token-set-led-fn token (math-get-table id math-led-fn-table))
    (setq math--tok math--next-tok)
    (setq math--next-tok token)))

(defun math-parse-peek-led-left-bp ()
  "The left binding power of the next token."
  (let* ((id (math-token-id math--next-tok))
	 (bp (math-get-table id math-led-left-bp-table)))
    (if bp bp (math-parse-error 
	       (format "No left binding power for operator `%s'." id) 
	       math--next-tok))))

(defun math-parse-peek-led-id ()
  "The id of next token to be read."
  (math-token-id math--next-tok))

(defun math-parse-expect-closer (closer)
  (math-parse-advance-token)
  (let ((id (math-token-id math--tok)))
    (unless (equal id closer)
      (math-parse-error 
       (format "Exepcted matching %s but read %s instead" closer id) 
       math--tok))))

(defun math-parse-expect-separator (closer)
  (math-parse-advance-token)
  (let ((id (math-token-id math--tok)))
    (unless (equal id closer)
      (math-parse-error (format "Exepcted %s but read %s instead" closer id) math--tok))))
  
(defun math-parse-expression (right-bp)
  "Parse an expression."
  ;; Get the first token of the expression.
  (math-parse-advance-token)

  ;; Incomplete Mathematica expressions can be continued on the next
  ;; line. Since we are trying to parse an expression, skip over the
  ;; eol markers.
  (while (equal (math-token-class math--tok) :eol)
    (math-parse-advance-token))

  ;; If we see an eof marker here, then this expression is incomplete.
  (if (equal (math-token-class math--tok) :eof)
      (math-parse-error "Incomplete expression" token))

  ;; Get the nud function for parsing the current token.
  (let ((nud (math-token-nud-fn math--tok)))
    (unless nud 
      (math-parse-error 
       (format "No nud function for `%s'" (math-token-source math--tok)) 
       math--tok))

    ;; Apply the nud function to get the parsed left sub-expression.
    (let ((subexpr (funcall nud math--tok)))

      ;; As long as the next token's binding power is higher than the
      ;; current right-bp, keep processing led expressions.
      (while (< right-bp (math-parse-peek-led-left-bp))

	  ;; Get the next token.
	  (math-parse-advance-token)

	  ;; Gett the led function for parsing the current token.
	  (let ((led (math-token-led-fn math--tok)))
	    (unless led
	      (math-parse-error
	       (format "No led function for `%s'" (math-token-source math--tok))
	       math--tok))
	    
	    (setq subexpr (funcall led subexpr math--tok))))
      subexpr)))

(defun math-parse-statement ()
  "Parse a Mathematica statement."

  ;; Discard blank lines.
  (while (equal (math-token-class math--next-tok) :eol)
    (math-parse-advance-token))

  ;; Read expressions until we find an eol or eof terminated expression.
  (let ((expressions (list 'expressions)))
    (while (and (not (equal (math-token-class math--next-tok) :eol))
		(not (equal (math-token-class math--next-tok) :eof)))
      (math-append-to-list expressions (math-parse-expression 0))
      ;; The expression must be terminated by one of: `;' `eol' `eof'.
      (let ((id (math-token-id math--next-tok)))
	(cond
	 ;; Consume the `;'
	 ((equal id ";") 
	  (math-parse-advance-token))
	 ;; The eol marker will cause the while loop to terminate.
	 ((equal id :eol)
	  t)
	 ;; The eof marker will cause the while loop to terminate.
	 ((equal id :eof)
	  t)
	 ;; Otherwise, there is a syntax error.
	 (t
	  (math-parse-error 
	   (format "Expected a `;' but read `%s' instead." id)
	   math--next-tok)))))

    ;; Discard blank lines.
    (while (equal (math-token-class math--next-tok) :eol)
      (math-parse-advance-token))

    expressions))

(defun math-parse-program ()
  "Parse a Mathematica program."
  
  (math-parse-init)
  ;; Read statements until we see the `eof' token.
  (let ((statements (list 'statements)))
    (while (not (equal (math-token-class math--next-tok) :eof))
      (math-append-to-list statements (math-parse-statement)))
    statements))

(defun math-parse-buffer ()
  (interactive)
  (save-excursion
    (goto-char (point-min))
    (with-output-to-temp-buffer "*math-parse-output*"
      (princ (math-parse-program)))))

(defun math-parse-region (begin end)
  (interactive "r")
  (save-excursion
    (save-restriction
      (narrow-to-region begin end)
      (goto-char (point-min))
      (let ((input (buffer-string)))
	(with-output-to-temp-buffer "*math-parse-output*"
	  (princ "Input:\n\n")
	  (princ input)
	  (princ "\n\n")
	  (princ "Parse:\n\n")
	  (pp (math-parse-program)))))))


;; Operator Definitions.
;;
(setq math-nud-left-bp-table (make-hash-table :test 'equal))
(setq math-nud-fn-table (make-hash-table :test 'equal))
(setq math-led-left-bp-table (make-hash-table :test 'equal))
(setq math-led-fn-table (make-hash-table :test 'equal))

;; Literals
;;
(math-register-nud :identifier 0 'math-parse-nud-literal)
(math-register-nud :string 0 'math-parse-nud-literal)
(math-register-nud :number 0 'math-parse-nud-literal)
(math-register-nud "\\[Infinity]"' 0 'math-parse-nud-literal)

;; expr::string          --> MessageName[expr,"string"]
;; expr::string::string  --> MessageName[expr,"string"]
(math-register-led-left "::" 780)

;; name[expr1,expr2,...]
;;
(math-register-led "[" 745 'math-parse-led-sequence)

;; ?? Grouping operators ?? I do not know where these should go.
(math-register-nud "(" 745 'math-parse-nud-paren)
(math-register-nud "{" 745 'math-parse-nud-curly)


;; expr1 /@  expr2  -->  Map[expr1,expr2]
;; expr1 //@ expr2  -->  MapAll[expr1,expr2]
;; expr1 @@  expr2  -->  Apply[expr1,expr2]
;; expr1 @@@ expr2  -->  Apply[expr1,expr2,{1}]
(math-register-led-right "/@" 640)
(math-register-led-right "//@" 640)
(math-register-led-right "@@" 640)
(math-register-led-right "@@@" 640)

;; Unary mathematical operators
;;
(math-register-nud-prefix "+" 490)
(math-register-nud-prefix "-" 490)

;; Binary mathematical operators
;;
(math-register-led-flat "+" 330)
(math-register-led-flat "-" 330)
(math-register-led-left "*" 410)
(math-register-led-left "/" 480)
(math-register-led-right "^" 590)

;; expr..                   --> Repeated[expr]
;; expr...                  --> RepeatedNull[expr]
(math-register-led-postfix ".." 170)
(math-register-led-postfix "..." 170)

;; expr1|expr2              --> Alternatives[expr1,expr2] 
(math-register-led-flat "|" 160)

;; symb:expr                --> Pattern[symb,expr]
;; patt:expr                --> Optional[patt,expr]
(math-register-led-left ":" 150)

;; expr1 -> expr2    --> Rule[expr1,expr2]
;; expr1 :> expr2    --> RuleDelayed[expr1,expr2]
(math-register-led-right "->" 120)
(math-register-led-right ":>" 120)

;; expr1   = expr2          --> Set[expr1,expr2]
;; expr1  := expr2          --> SetDelayed[expr1,expr2]
;; expr1  ^= expr2          --> Upset[expr1,expr2]
;; expr1 ^:= expr2          --> UpsetDelayed[expr1,expr2]
;; expr =.                  --> Uset[expr]
;; expr1 |-> expr2          --> Function[{expr1},expr2]
;; symb /: expr1  = expr2   --> TagSet[symb,expr1,expr2]
;; symb /: expr1 := expr2   --> TagSetDelayed[symb,expr1,expr2]
;; symb /: expr1 =.         --> TagUnset[expr]
(math-register-led-right "=" 40)
(math-register-led-right ":=" 40)
(math-register-led-right "^=" 40)
(math-register-led-right "=." 40)
(math-register-led-right "|->" 40)

;; expr>>filename      --> Put[expr,"filename"]
;; expr>>>filename     --> PutAppend[expr,"filename"]
(math-register-led-left ">>" 30)
(math-register-led-left ">>>" 30)

;; expr1;expr2;expr3   --> CompoundExpression[expr1,expr2,expr3]
;; expr1;expr2;        --> CompoundExpression[expr1,expr2,Null]
;;
;; TODO - add lookahead in tokenizer for ws to eol so that the eos
;; parser can check for the second version and add the Null marker.
;;(math-register-led-flat ";" 20)

;; expr1 \` expr2      --> FormBoxp[expr2,expr1]
(math-register-led-right "\\`" 10)

;; Separators need to be registered.
(math-register-symbol ",")

;; Closers need to be registered.
(math-register-symbol ";")
(math-register-symbol "]")
(math-register-symbol ")")
(math-register-symbol "}")
(math-register-symbol :eof)
(math-register-symbol :eol)


(provide 'math-parse)
