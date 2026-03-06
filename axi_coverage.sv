class axi_coverage extends uvm_subscriber #(axi_item);
  `uvm_component_utils(axi_coverage)

  covergroup cg with function sample(axi_item t);
    option.per_instance = 1;
    dir_cp   : coverpoint t.dir;
    burst_cp : coverpoint t.burst;
    size_cp  : coverpoint t.size { bins b[] = {0,1,2}; bins illegal = default; }
    len_cp   : coverpoint t.len  { bins small[] = {0,1,3}; bins med[] = {7}; bins big[] = {15}; }
    cross dir_cp, burst_cp, size_cp, len_cp;
  endgroup

  function new(string name, uvm_component parent);
    super.new(name,parent);
    cg = new();
  endfunction

  virtual function void write(axi_item t);
    cg.sample(t);
  endfunction
endclass