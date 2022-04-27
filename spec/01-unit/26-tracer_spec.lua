require "spec.helpers" -- initializes 'kong' global for tracer

describe("Tracer PDK", function()
  local ok, _

  lazy_setup(function()
    local kong_global = require "kong.global"
    _G.kong = kong_global.new()
    kong_global.init_pdk(kong)
  end)

  describe("test tracer init", function()

    it("tracer instance is created", function ()
      ok, _ = pcall(require "kong.pdk.tracer".new)
      assert.is_true(ok)

      ok, _ = pcall(kong.tracer.new)
      assert.is_true(ok)
    end)

    it("default tracer instance", function ()
      local tracer
      ok, tracer = pcall(require "kong.pdk.tracer".new)
      assert.is_true(ok)
      assert.is_true(tracer.noop)
      assert.same("core", tracer.name)
    end)

  end)

  describe("span spec", function ()
    -- common tracer
    local c_tracer = kong.tracer.new("normal")
    -- noop tracer
    local n_tracer = require "kong.pdk.tracer".new()

    before_each(function()
      ngx.ctx.active_span = nil
    end)

    it("fails when span name is empty", function ()
      -- create 
      ok, _ = pcall(c_tracer.start_span)
      assert.is_false(ok)

      -- 0-length name
      ok, _ = pcall(c_tracer.start_span, "")
      assert.is_false(ok)
    end)

    it("create noop span with noop tracer", function ()
      local span = n_tracer.start_span("meow")
      ok, _ = pcall(span.noop) -- __index
      assert.is_true(ok)
    end)

    it("noop span operations", function ()
      local span = n_tracer.start_span("meow")
      assert(pcall(span.set_attribute, span, "foo", "bar"))
      assert(pcall(span.add_event, span, "foo", "bar"))
      assert(pcall(span.finish, span))
      assert(pcall(span.any, span))
    end)

    it("fails create span with options", function ()
      assert.error(function () c_tracer.start_span("") end)
      assert.error(function () c_tracer.start_span("meow", { start_time_ns = "" }) end)
      assert.error(function () c_tracer.start_span("meow", { span_kind = "" }) end)
      assert.error(function () c_tracer.start_span("meow", { sampled = "" }) end)
      assert.error(function () c_tracer.start_span("meow", { attributes = "" }) end)
    end)

    it("default span value length", function ()
      local span
      span = c_tracer.start_span("meow")
      assert.same(16, #span.trace_id)
      assert.same(8, #span.span_id)
      assert.is_true(span.start_time_ns > 0)
    end)

    it("create span with options", function ()
      local span

      local tpl = {
        name = "meow",
        trace_id = "000000000000",
        start_time_ns = ngx.now() * 100000000,
        parent_id = "",
        sampled = true,
        kind = 1,
        attributes = {
          "key1", "value1"
        },
      }

      span = c_tracer.start_span("meow", tpl)
      local c_span = table.clone(span)
      c_span.tracer = nil
      c_span.span_id = nil
      assert.same(tpl, c_span)

      assert.has_no.error(function () span:finish() end)
    end)

    it("fails set_attribute", function ()
      local span = c_tracer.start_span("meow")
      assert.error(function() span:set_attribute("key1") end)
      assert.error(function() span:set_attribute("key1", function() end) end)
      assert.error(function() span:set_attribute(123, 123) end)
    end)

    it("fails add_event", function ()
      local span = c_tracer.start_span("meow")
      assert.error(function() span:set_attribute("key1") end)
      assert.error(function() span:set_attribute("key1", function() end) end)
      assert.error(function() span:set_attribute(123, 123) end)
    end)

    it("child spans", function ()
      local root_span = c_tracer.start_span("parent")
      local child_span = c_tracer.start_span("child")

      assert.same(root_span.span_id, child_span.parent_id)

      local second_child_span = c_tracer.start_span("child2")
      assert.same(root_span.span_id, second_child_span.parent_id)
      assert.are_not.same(child_span.span_id, second_child_span.parent_id)

      c_tracer.set_active_span(child_span)
      local third_child_span = c_tracer.start_span("child2")
      assert.same(child_span.span_id, third_child_span.parent_id)
    end)

    it("clear span table when finished", function ()
      local span = c_tracer.start_span("meow")

      -- span table is released, the value is empty
      span:finish()
      assert.same({}, span)

      -- span is not accessible (metatable is cleard)
      assert.error(function () span:finish() end)
    end)

  end)

end)
