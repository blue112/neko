open Ast

type error_msg =
	| Unexpected of token
	| Unclosed of string
	| Duplicate_default
	| Unknown_macro of string
	| Invalid_macro_parameters of string * int

exception Error of error_msg * pos

let error_msg = function
	| Unexpected t -> "Unexpected "^(s_token t)
	| Unclosed s -> "Unclosed " ^ s
	| Duplicate_default -> "Duplicate default declaration"
	| Unknown_macro m -> "Unknown macro " ^ m
	| Invalid_macro_parameters (m,n) -> "Invalid number of parameters for macro " ^ m ^ " : " ^ string_of_int n ^ " required"

let error m p = raise (Error (m,p))

let priority = function
	| "=" | "+=" | "-=" | "*=" | "/=" | "|=" | "&=" | "^=" -> -3
	| "&&" | "||" -> -2
	| "==" | "!=" | ">" | "<" | "<=" | ">=" -> -1
	| "+" | "-" -> 0
	| "*" | "/" -> 1
	| "|" | "&" | "^" -> 2
	| "<<" | ">>" | "%" | ">>>" -> 3
	| _ -> 4

let rec make_binop op e ((v,p2) as e2) =
	match v with
	| EBinop (_op,_e,_e2) when priority _op <= priority op ->
		let _e = make_binop op e _e in
		EBinop (_op,_e,_e2) , punion (pos _e) (pos _e2)
	| _ ->
		EBinop (op,e,e2) , punion (pos e) (pos e2)

let rec program = parser
	| [< e = expr; p = program >] -> e :: p
	| [< '(Semicolon,_); p = program >] -> p
	| [< '(Eof,_) >] -> []

and expr = parser	
	| [< '(Const c,p); s >] ->
		expr_next (EConst c,p) s
	| [< '(BraceOpen,p1); p = block; s >] ->
		(match s with parser
		| [< '(BraceClose,p2); s >] -> expr_next (EBlock p,punion p1 p2) s
		| [< _ = expr >] -> error (Unclosed "{") p1)
	| [< '(ParentOpen,p1); e = expr; s >] ->
		(match s with parser
		| [< '(ParentClose,p2); s >] -> expr_next (EParenthesis e,punion p1 p2) s
		| [< _ = expr >] -> error (Unclosed "(") p1)
	| [< '(Keyword Var,p1); v, p2 = variables p1; s >] ->
		expr_next (EVars v,punion p1 p2) s
	| [< '(Keyword For,p1); '(ParentOpen,po); e1 = expr; e2 = expr; e3 = expr; s >] ->
		(match s with parser
		| [< '(ParentClose,_); e = expr; s >] -> expr_next (EFor (e1,e2,e3,e),punion p1 (pos e)) s
		| [< _ = expr >] -> error (Unclosed "(") po)
	| [< '(Keyword While,p1); cond = expr; e = expr; s >] ->
		expr_next (EWhile (cond,e,NormalWhile), punion p1 (pos e)) s
	| [< '(Keyword Do,p1); e = expr; '(Keyword While,_); cond = expr; s >] ->
		expr_next (EWhile (cond,e,DoWhile), punion p1 (pos cond)) s
	| [< '(Keyword If,p1); cond = expr; e = expr; s >] ->
		(match s with parser
		| [< '(Keyword Else,_); e2 = expr; s >] -> expr_next (EIf (cond,e,Some e2),punion p1 (pos e2)) s
		| [< >] -> expr_next (EIf (cond,e,None),punion p1 (pos e)) s)
	| [< '(Keyword Function,p1); '(ParentOpen,po); p = parameter_names; s >] ->
		(match s with parser
		| [< '(ParentClose,_); e = expr; s >] -> expr_next (EFunction (p,e),punion p1 (pos e)) s
		| [< _ = expr >] -> error (Unclosed "(") po)
	| [< '(Keyword Return,p1); s >] ->
		(match s with parser
		| [< e = expr; s >] -> expr_next (EReturn (Some e), punion p1 (pos e)) s
		| [< '(Semicolon,_); s >] -> expr_next (EReturn None,p1) s)
	| [< '(Keyword Break,p1); s >] ->
		(match s with parser
		| [< e = expr; s >] -> expr_next (EBreak (Some e), punion p1 (pos e)) s
		| [< '(Semicolon,_); s >] -> expr_next (EBreak None,p1) s)
	| [< '(Keyword Continue,p1); s >] ->
		expr_next (EContinue,p1) s
	| [< '(Keyword Try,p1); e = expr; '(Keyword Catch,_); '(Const (Ident name),_); e2 = expr; s >] ->
		expr_next (ETry (e,name,e2),punion p1 (pos e2)) s

and expr_next e = parser
	| [< '(Dot,_); '(Const (Ident name),p); s >] ->
		expr_next (EField (e,name),punion (pos e) p) s
	| [< '(ParentOpen,po); pl = parameters; s >] ->
		(match s with parser
		| [< '(ParentClose,p); s >] -> expr_next (ECall (e,pl),punion (pos e) p) s
		| [< _ = expr >] -> error (Unclosed "(") po)
	| [< '(BracketOpen,po); e2 = expr; s >] ->
		(match s with parser
		| [< '(BracketClose,p); s >] -> expr_next (EArray (e,e2),punion (pos e) p) s
		| [< _ = expr >] -> error (Unclosed "[") po)
	| [< '(Binop op,_); e2 = expr; s >] ->
		make_binop op e e2
	| [< >] -> e

and block = parser
	| [< e = expr; b = block >] -> e :: b
	| [< '(Semicolon,_); b = block >] -> b
	| [< >] -> []

and parameter_names = parser
	| [< '(Const (Ident name),_); p = parameter_names >] -> name :: p
	| [< '(Comma,_); p = parameter_names >] -> p
	| [< >] -> []

and parameters = parser
	| [< e = expr; p = parameters >] -> e :: p
	| [< '(Comma,_); p = parameters >] -> p
	| [< >] -> []

and variables sp = parser
	| [< '(Const (Ident name),p); s >] ->
		(match s with parser
		| [< '(Binop "=",_); e = expr; v , p = variables (pos e) >] -> (name, Some e) :: v , p
		| [< >] -> variables p s)
	| [< '(Comma,p); v = variables p >] -> v
	| [< >] -> [] , sp

let parse code file =
	let old = Lexer.save() in
	Lexer.init file;
	let last = ref (Eof,null_pos) in
	let rec next_token x =
		let t, p = Lexer.token code in
		match t with
		| Comment s | CommentLine s -> 
			next_token x
		| _ ->
			last := (t , p);
			Some (t , p)
	in
	try
		let l = program (Stream.from next_token) in
		Lexer.restore old;
		EBlock l, { pmin = 0; pmax = (pos !last).pmax; pfile = file }
	with
		| Stream.Error _
		| Stream.Failure -> 
			Lexer.restore old;
			error (Unexpected (fst !last)) (pos !last)
		| e ->
			Lexer.restore old;
			raise e

let expand_macro ctx m params p =
	let fparams, fe = (try List.assoc m ctx with Not_found -> error (Unknown_macro m) p) in
	if List.length params <> List.length fparams then error (Invalid_macro_parameters (m,List.length fparams)) p;
	let ctx = ref (List.map2 (fun p name -> (name,p)) params fparams) in
	let rec loop (e,p) =
		match e with
		| EBlock el ->
			let old = !ctx in
			let el = List.map loop el in
			ctx := old;
			EBlock el , p
		| EVars vl ->
			EVars (List.map (fun (v,ve) ->
				let ve = (match ve with None -> None | Some e -> Some (loop e)) in
				ctx := List.filter (fun (i,_) -> i <> v) !ctx;
				v , ve
			) vl) , p
		| EConst (Ident i) ->
			(try
				List.assoc i !ctx
			with	
				Not_found -> (e,p))
		| _ ->
			Ast.map loop (e,p)
	in
	loop fe

let expand e = 
	let ctx = ref [] in
	let rec loop (e,p) =
		match e with
		| EBlock el -> 
			let old = !ctx in
			let el = List.map loop el in
			ctx := old;
			EBlock el , p
		| EVars vl ->
			let vl = List.map (fun (v,ve) ->
				match ve with
				| None -> v , None
				| Some e ->
					let e = loop e in
					(match e with EFunction (params,fe) , _ -> ctx := (v,(params,fe)) :: !ctx | _ -> ());
					v , Some e
			) vl in
			EVars vl , p
		| ECall ((EConst (Macro m),mp),params) ->
			expand_macro !ctx m params mp
		| EConst (Macro m) ->
			expand_macro !ctx m [] p
		| _ ->
			Ast.map loop (e,p)
	in
	loop e