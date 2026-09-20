import "laya-lib" as lib;

to_entries
| map({id: ("m1-" + (.key|tostring)), value: .value})
| map(.value + {id: .id})
| (lib::split_stratified(.; "id"; "outcome")) as $split
| $split
