(*
 Jubatus: Online machine learning framework for distributed environment
 Copyright (C) 2011,2012 Preferred Infrastructure and Nippon Telegraph and Telephone Corporation.

 This library is free software; you can redistribute it and/or
 modify it under the terms of the GNU Lesser General Public
 License as published by the Free Software Foundation; either
 version 2.1 of the License, or (at your option) any later version.

 This library is distributed in the hope that it will be useful,
 but WITHOUT ANY WARRANTY; without even the implied warranty of
 MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 Lesser General Public License for more details.

 You should have received a copy of the GNU Lesser General Public
 License along with this library; if not, write to the Free Software
 Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301  USA
*)

open Util
open Stree

let comment =
  "// this program is automatically generated by jenerator. do not edit.";;

class spec n i f b = object
  method namespace : string = n
  method internal  : bool   = i
  method filename  : string = f
  method basename  : string = b
end;;

let is_service = function
  | Service(_,_) -> true;
  | _ -> false;;

let parse_decorators decorators =
(* FIXME: you should use pattern matching against decorators, instead *)
  let routing =
    let s = List.nth decorators 0 in String.sub s 2 (String.length s - 2)
  in
  let rwtype =
    let s = List.nth decorators 1 in String.sub s 2 (String.length s - 2)
  in
  let agg =
    let s = List.nth decorators 2 in String.sub s 2 (String.length s - 2)
  in
  (routing,rwtype,agg);;

exception Bad_container of string

let to_keeper_strings = function
  | Service(_, methods) ->
    let to_keeper_string (Method(rettype0, name, argv, decorators)) =
      let routing,rwtype,agg = parse_decorators decorators in
      let rettype = Util.decl_type2string rettype0 in
      let sorted_argv = List.sort
	(fun lhs rhs -> let Field(l,_,_) = lhs in let Field(r,_,_) = rhs in l-r ) argv
      in
      let argv_types = List.map
	(fun field -> let Field(_,t,_) = field in t) (List.tl sorted_argv)
      in
      let argv_strs = List.map Util.decl_type2string argv_types in

      match routing with
	| "random" -> 
	  Printf.sprintf "  k.register_%s<%s >(\"%s\"); //%s %s"
	    routing (String.concat ", " (rettype::argv_strs))  name agg rwtype;
	| "cht" -> (* when needs aggregator *)
	  let aggfunc =
	    let tmpl =
	      (* merge for map, concat for list *)
	      match rettype0 with (* FIXME: this should be fixed up as Util *)
		| Map(k,v) -> "<"^(Util.decl_type2string k)^","^(Util.decl_type2string v)^" >" ;
		| List t ->  "<"^(Util.decl_type2string t)^" >" ;
		| _ when agg = "random" -> "<"^rettype^" >" ;
		| _ -> "" (* FIXME, dangerous *)
	    in
	    Printf.sprintf "pfi::lang::function<%s(%s,%s)>(&%s%s)" rettype rettype rettype agg tmpl
	  in
	  Printf.sprintf "  k.register_%s<%s >(\"%s\", %s); //%s"
	    routing (String.concat ", " (rettype::(List.tl argv_strs)))  name aggfunc rwtype
	| _ ->
	  let aggfunc =
	    let tmpl =
	      (* merge for map, concat for list *)
	      match rettype0 with
		| Map(k,v) -> "<"^(Util.decl_type2string k)^","^(Util.decl_type2string v)^" >" ;
		| List(t) ->  "<"^(Util.decl_type2string t)^" >" ;
		| _ when agg = "random" -> "<"^rettype^" >" ;
		| _ -> "" (* FIXME, dangerous *)
	    in
	    Printf.sprintf "pfi::lang::function<%s(%s,%s)>(&%s%s)" rettype rettype rettype agg tmpl
	  in
	  Printf.sprintf "  k.register_%s<%s >(\"%s\", %s); //%s"
	    routing (String.concat ", " (rettype::argv_strs))  name aggfunc rwtype
    in
    List.map to_keeper_string methods;
  | _ -> [];;

let generate_keeper s output strees =
  output <<< comment;
  
  if s#internal then begin
    output <<< "#include \"../framework/keeper.hpp\"";
    output <<< "#include \"../framework/aggregators.hpp\""
  end
  else begin
    output <<< "#include <jubatus/framework.hpp>";
    output <<< "#include <jubatus/framework/aggregators.hpp>"
  end;
  
  output <<< ("#include \""^s#basename^"_types.hpp\"");
  output <<< ("using namespace "^s#namespace^";");
  output <<< "using namespace jubatus::framework;";
  output <<< "int main(int args, char** argv){";
  output <<< "  keeper k(keeper_argv(args,argv));";

  List.iter (fun l -> output <<< l)
    (List.flatten (List.map to_keeper_strings
		     (List.filter is_service strees)));
  
  output <<< "  k.run();";
  output <<< "}";;

exception Wrong_rwtype of string

let to_impl_strings = function
  | Service(_, methods) ->
    let to_keeper_string m =
      let Method(rettype, name, argv, decorators) = m in
      let routing,rwtype,_ = parse_decorators decorators in

      let rettype = Util.decl_type2string rettype in
      let sorted_argv = List.sort
	(fun lhs rhs -> let Field(l,_,_) = lhs in let Field(r,_,_) = rhs in l-r ) argv
      in
      let argv_strs = List.map
	(fun field -> let Field(_,t,n) = field in (decl_type2string t)^" "^n) sorted_argv
      in
      let argv_strs2 = List.map
	(fun field -> let Field(_,_,n) = field in n) (List.tl sorted_argv)
      in
      let lock_str = match rwtype with
	|"update" -> "JWLOCK__";
	|"analysis"->"JRLOCK__";
	|_ -> raise (Wrong_rwtype (rwtype ^" for "^ name))
      in
      
      (Printf.sprintf "\n  %s %s(%s) //%s %s" rettype name (String.concat ", " argv_strs) rwtype routing)
	^(Printf.sprintf "\n  { %s(p_); return p_->%s(%s); }" lock_str name (String.concat ", " argv_strs2))
	
    in
    List.map to_keeper_string methods;
  | _ -> [];;

let generate_impl s output strees =
  output <<< comment;

  if s#internal then
    output <<< "#include \"../framework.hpp\""
  else
    output <<< "#include <jubatus/framework.hpp>";

  output <<< ("#include \""^s#basename^"_server.hpp\"");
  output <<< ("#include \""^s#basename^"_serv.hpp\"");
  output <<< ("using namespace "^s#namespace^";");
  output <<< "using namespace jubatus::framework;";

  output <<< "namespace jubatus { namespace server {";
  output <<< ("class "^s#basename^"_impl_ : public "^s#basename^"<"^s#basename^"_impl_>");
  output <<< "{";
  output <<< "public:";
  output <<< ("  "^s#basename^"_impl_(const server_argv& a):");
  output <<< ("    "^s#basename^"<"^s#basename^"_impl_>(a.timeout),");
  output <<< ("    p_(new "^s#basename^"_serv(a))");

  let use_cht =
    let include_cht_api = function
      | Service(_, methods) ->
	List.exists (fun m -> let Method(_,_,_,decs) = m in List.mem "#@cht" decs) methods;
      | _ -> false
    in
    if List.exists include_cht_api strees then " p_->use_cht();"
    else ""
  in
  output <<< ("  {" ^ use_cht ^ "}");

  List.iter (fun l -> output <<< l)
    (List.flatten (List.map to_impl_strings
		     (List.filter is_service strees)));

  output <<< "  int run(){ return p_->start(*this); };";
  output <<< ("  pfi::lang::shared_ptr<"^s#basename^"_serv> get_p(){ return p_; };");
  output <<< "private:";
  output <<< ("  pfi::lang::shared_ptr<"^s#basename^"_serv> p_;");
  output <<< "};";
  output <<< "}} // namespace jubatus::server";

  output <<< "int main(int args, char** argv){";
  output <<< "  return";
  
  output <<< "    jubatus::framework::run_server<jubatus::server::"^s#basename^"_impl_,";
  output <<< "                                   jubatus::server::"^s#basename^"_serv>";
  output <<< "       (args, argv);";
  output <<< "}";;

let to_tmpl_strings = function
  | Service(_, methods) ->
    let to_tmpl_string m =
      let Method(rettype, name, argv, decorators) = m in
      let routing,rwtype,_ = parse_decorators decorators in
      let rettype = Util.decl_type2string rettype in
      let sorted_argv = List.sort
	(fun lhs rhs -> let Field(l,_,_) = lhs in let Field(r,_,_) = rhs in l-r ) argv
      in
      let argv_strs = List.map
	(fun field -> let Field(_,t,n) = field in (decl_type2string_const_ref t)^" "^n) (List.tl sorted_argv)
      in
      let const_str = match rwtype with
	|"update" -> "";
	|"analysis"->" const";
	|_ -> raise (Wrong_rwtype (rwtype ^" for "^ name))
      in

      (Printf.sprintf "\n  %s %s(%s)%s; //%s %s"
	 rettype name (String.concat ", " argv_strs) const_str rwtype routing)
    in
    List.map to_tmpl_string methods;
  | _ -> [];;

let generate_server_tmpl_header s output strees =
  output <<< "// this is automatically generated template header please implement and edit.";

  output <<< "#pragma once";
  if s#internal then
    output <<< "#include \"../framework.hpp\""
  else
    output <<< "#include <jubatus/framework.hpp>";
  output <<< ("#include \""^s#basename^"_types.hpp\"");

  output <<< "using namespace jubatus::framework;\n";
  output <<< "namespace jubatus { namespace server { // do not change";
  output <<< ("class "^s#basename^"_serv : public jubatus_serv // do not change");
  output <<< "{";
  output <<< "public:";
  output <<< ("  "^s#basename^"_serv(const server_argv& a); // do not change");
  output <<< ("  virtual ~"^s#basename^"_serv(); // do not change");

  List.iter (fun l -> output <<< l)
    (List.flatten (List.map to_tmpl_strings
		     (List.filter is_service strees)));

  output <<< "  void after_load();";
  output <<< "";
  output <<< "private:";
  output <<< "  // add user data here like: pfi::lang::shared_ptr<some_type> some_;";
  output <<< "};";
  output <<< "}} // namespace jubatus::server";;

let to_impl_strings classname = function
  | Service(_, methods) ->
    let to_impl_string m =
      let Method(rettype, name, argv, decorators) = m in
      let routing,rwtype,_ = parse_decorators decorators in
      let rettype = Util.decl_type2string rettype in
      let sorted_argv = List.sort
	(fun lhs rhs -> let Field(l,_,_) = lhs in let Field(r,_,_) = rhs in l-r ) argv
      in
      let argv_strs = List.map
	(fun field -> let Field(_,t,n) = field in (decl_type2string_const_ref t)^" "^n) (List.tl sorted_argv)
      in
      let const_str = match rwtype with
	|"update" -> "";
	|"analysis"->" const";
	|_ -> raise (Wrong_rwtype (rwtype ^" for "^ name))
      in

      (Printf.sprintf "\n//%s, %s\n%s %s::%s(%s)%s\n{}"
	 rwtype routing rettype classname name (String.concat ", " argv_strs) const_str)
    in
    List.map to_impl_string methods;
  | _ -> [];;


let generate_server_tmpl_impl s output strees =
  output <<< "// this is automatically generated template header please implement and edit.\n";

  let classname = s#basename^"_serv" in
  output <<< ("#include \""^classname^".hpp\"\n");

  output <<< "using namespace jubatus::framework;\n";
  output <<< "namespace jubatus { namespace server { // do not change";

  output <<< (classname^"::"^classname^"(const server_argv& a)");
  output <<< "  :framework::jubatus_serv(a)";
  output <<< "{";
  output <<< "  //somemixable* mi = new somemixable;";
  output <<< "  //somemixable_.set_model(mi);";
  output <<< "  //register_mixable(framework::mixable_cast(mi));";
  output <<< "}\n";

  output <<< (classname^"::~"^classname^"()");
  output <<< "{}\n";

  List.iter (fun l -> output <<< l)
    (List.flatten (List.map (to_impl_strings classname)
		     (List.filter is_service strees)));

  output <<< "";

  output <<< ("void "^classname^"::after_load(){}");

  output <<< "}} // namespace jubatus::server";;

(*
  method set_output filename =
    if debugmode then
      output <- stdout
    else
      output <- open_out filename
*)
