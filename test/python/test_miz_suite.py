"""Tests for the parts of build-tools/miz-suite.py that read and rewrite a mission.

Run from anywhere:

    python -m unittest discover -s test/python

The tool edits binary archives, and its whole job is regular expressions over a `mission` that two
different tools write in two different shapes -- DCS's own serialisation, and the one VEAF's mission
editor produces when it re-saves a mission. A pattern that matches the wrong block does not raise:
it rewrites the wrong trigger, writes the archive, and the mission is wrong in DCS.

The fragments below are cut down from the real archives. The nested `ai_task` table inside an action
is there on purpose: it is what the indentation anchoring in ACTION_BLOCKS protects against, since a
non-greedy body would otherwise stop at that table's closing brace.
"""

import importlib.util
import os
import unittest

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
_spec = importlib.util.spec_from_file_location("miz_suite", os.path.join(ROOT, "build-tools", "miz-suite.py"))
ms = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(ms)


#: How DCS writes it: bracketed keys, and an `-- end of [n]` comment closing every block.
#:
#: DCS leaves a **trailing space** after `=` on every multi-line assignment, and the patterns
#: match it. A fixture holding real trailing spaces would not survive an editor that strips them,
#: so they are put back below rather than written here.
_DCS_MISSION = '''mission =
{
    ["trig"] =
    {
        ["actions"] =
        {
            [1] = "a_do_script_file(getValueResourceByKey(\\"ResKey_Action_317\\"));a_do_script_file(getValueResourceByKey(\\"ResKey_Action_172\\"));",
        }, -- end of ["actions"]
    }, -- end of ["trig"]
    ["trigrules"] =
    {
        [1] =
        {
            ["actions"] =
            {
                [1] =
                {
                    ["file"] = "ResKey_Action_317",
                    ["predicate"] = "a_do_script_file",
                }, -- end of [1]
                [2] =
                {
                    ["ai_task"] =
                    {
                        [1] = "",
                    }, -- end of ["ai_task"]
                    ["file"] = "ResKey_Action_172",
                    ["predicate"] = "a_do_script_file",
                }, -- end of [2]
            }, -- end of ["actions"]
            ["comment"] = "Load SKYNET",
        }, -- end of [1]
    }, -- end of ["trigrules"]
    ["version"] = 22,
} -- end of mission
'''
DCS_MISSION = _DCS_MISSION.replace("=\n", "= \n")

#: How VEAF's mission editor writes the same thing: bare keys, no end-of-block comments, and a
#: resource key of its own that is not a `ResKey_Action_NNN` at all.
EDITOR_MISSION = '''mission = {
  trig = {
    actions = {
      [1] = "a_do_script_file(getValueResourceByKey(\\"ResKey_Action_317\\"));a_do_script_file(getValueResourceByKey(\\"ResKey_Action_172\\"));",
      [2] = "a_do_script_file(getValueResourceByKey(\\"MCP_MapKey_dcs-bridge\\"));",
    },
  },
  trigrules = {
    [1] = {
      actions = {
        [1] = {
          file = "ResKey_Action_317",
          predicate = "a_do_script_file",
        },
        [2] = {
          ai_task = {
            [1] = "",
          },
          file = "ResKey_Action_172",
          predicate = "a_do_script_file",
        },
      },
      comment = "Load SKYNET",
    },
    [2] = {
      actions = {
        [1] = {
          file = "MCP_MapKey_dcs-bridge",
          predicate = "a_do_script_file",
        },
      },
      comment = "dcs-bridge",
    },
  },
  version = 22,
}
'''

_DCS_MAP_RESOURCE = '''mapResource =
{
    ["ResKey_Action_317"] = "mist_4_5_107.lua",
    ["ResKey_Action_172"] = "skynet-iads-compiled.lua",
} -- end of mapResource
'''
DCS_MAP_RESOURCE = _DCS_MAP_RESOURCE.replace("=\n", "= \n")

EDITOR_MAP_RESOURCE = '''mapResource =
{
  ["MCP_MapKey_dcs-bridge"] = "dcs-bridge.lua",
  ResKey_Action_172 = "skynet-iads-compiled.lua",
  ResKey_Action_317 = "mist_4_5_107.lua",
}
'''


class MapResource(unittest.TestCase):
    def test_reads_dcs_bracketed_keys(self):
        self.assertEqual(
            ms.parse_map_resource(DCS_MAP_RESOURCE),
            {"ResKey_Action_317": "mist_4_5_107.lua", "ResKey_Action_172": "skynet-iads-compiled.lua"},
        )

    def test_reads_the_editors_bare_keys_and_its_own(self):
        self.assertEqual(
            ms.parse_map_resource(EDITOR_MAP_RESOURCE),
            {
                "MCP_MapKey_dcs-bridge": "dcs-bridge.lua",
                "ResKey_Action_172": "skynet-iads-compiled.lua",
                "ResKey_Action_317": "mist_4_5_107.lua",
            },
        )

    def test_the_opening_line_is_not_an_entry(self):
        self.assertNotIn("mapResource", ms.parse_map_resource(EDITOR_MAP_RESOURCE))


class Trigrules(unittest.TestCase):
    def test_dcs_section_stops_at_its_end_comment(self):
        start, end = ms.trigrules_of(DCS_MISSION)
        section = DCS_MISSION[start:end]
        self.assertIn('["file"] = "ResKey_Action_317"', section)
        self.assertNotIn('["version"]', section)

    def test_editor_section_stops_at_the_next_key_at_the_same_depth(self):
        start, end = ms.trigrules_of(EDITOR_MISSION)
        section = EDITOR_MISSION[start:end]
        self.assertIn('file = "MCP_MapKey_dcs-bridge"', section)
        self.assertNotIn("version = 22", section)

    def test_a_mission_without_one_is_refused(self):
        with self.assertRaises(SystemExit):
            ms.trigrules_of("mission = {\n}\n")


class ActionBlocks(unittest.TestCase):
    """A block holding a nested table is one block, not two."""

    def blocks_of(self, mission):
        start, end = ms.trigrules_of(mission)
        arrays = ms.first_matching(ms.ACTIONS_ARRAYS, mission[start:end])
        return [ms.action_blocks(a.group("body") + "\n") for a in arrays]

    def test_dcs(self):
        self.assertEqual([len(b) for b in self.blocks_of(DCS_MISSION)], [2])

    def test_editor(self):
        self.assertEqual([len(b) for b in self.blocks_of(EDITOR_MISSION)], [2, 1])


class DropFromTrigrules(unittest.TestCase):
    """Taking a script out: the entry goes, what is left is renumbered, nothing else moves."""

    def test_dcs(self):
        after, removed = ms.drop_from_trigrules(DCS_MISSION, {"ResKey_Action_317"})
        self.assertEqual(removed, 1)
        self.assertNotIn("ResKey_Action_317", after.split('["trigrules"]')[1])
        self.assertIn('["file"] = "ResKey_Action_172"', after)
        # The entry that was [2] is now [1], comment included, or the editor shows an empty slot.
        self.assertIn("}, -- end of [1]\n", after)
        self.assertNotIn("end of [2]", after)
        self.assertIn('["version"] = 22', after)

    def test_editor(self):
        after, removed = ms.drop_from_trigrules(EDITOR_MISSION, {"ResKey_Action_317"})
        self.assertEqual(removed, 1)
        self.assertNotIn("ResKey_Action_317", after.split("trigrules = {")[1])
        self.assertIn('file = "ResKey_Action_172"', after)
        self.assertIn('[1] = {\n          ai_task = {', after)
        # The second trigrule is a different array and keeps its own numbering.
        self.assertIn('file = "MCP_MapKey_dcs-bridge"', after)
        self.assertIn("version = 22", after)

    def test_a_key_that_is_in_no_action_removes_nothing(self):
        after, removed = ms.drop_from_trigrules(EDITOR_MISSION, {"ResKey_Action_999"})
        self.assertEqual(removed, 0)
        self.assertEqual(after, EDITOR_MISSION)


class DropFromMapResource(unittest.TestCase):
    """Taking a key's line out, whichever tool wrote the file."""

    def test_dcs_brackets_every_key(self):
        after = ms.drop_from_map_resource(DCS_MAP_RESOURCE, "ResKey_Action_317")
        self.assertNotIn("ResKey_Action_317", after)
        self.assertIn('["ResKey_Action_172"] = "skynet-iads-compiled.lua"', after)

    def test_the_editor_leaves_most_keys_bare(self):
        after = ms.drop_from_map_resource(EDITOR_MAP_RESOURCE, "ResKey_Action_317")
        self.assertNotIn("ResKey_Action_317", after)
        self.assertIn('ResKey_Action_172 = "skynet-iads-compiled.lua"', after)

    def test_the_editor_brackets_a_key_that_needs_quoting(self):
        after = ms.drop_from_map_resource(EDITOR_MAP_RESOURCE, "MCP_MapKey_dcs-bridge")
        self.assertNotIn("dcs-bridge", after)
        self.assertIn('ResKey_Action_317 = "mist_4_5_107.lua"', after)

    def test_a_key_that_is_not_there_is_refused_rather_than_ignored(self):
        self.assertIsNone(ms.drop_from_map_resource(EDITOR_MAP_RESOURCE, "ResKey_Action_999"))


class SourceFolders(unittest.TestCase):
    """Where a member is looked for: its archive's directory, then the family's root."""

    def test_an_archive_at_the_root_of_its_family_lists_one_folder(self):
        self.assertEqual(ms.source_folders(os.path.join("unit-tests", "x.miz")), ["unit-tests"])

    def test_a_subdirectory_falls_back_to_the_family_root(self):
        self.assertEqual(
            ms.source_folders(os.path.join("demo-missions", "moose_a2a_connector", "x.miz")),
            [os.path.join("demo-missions", "moose_a2a_connector"), "demo-missions"],
        )

    def test_a_demo_never_looks_among_the_tests(self):
        self.assertNotIn("unit-tests", ms.source_folders(os.path.join("demo-missions", "x.miz")))


class Keys(unittest.TestCase):
    def test_the_loading_order_is_read_from_either_mission(self):
        for mission, expected in (
            (DCS_MISSION, ["ResKey_Action_317", "ResKey_Action_172"]),
            (EDITOR_MISSION, ["ResKey_Action_317", "ResKey_Action_172", "MCP_MapKey_dcs-bridge"]),
        ):
            import re

            self.assertEqual(
                re.findall(r'a_do_script_file\(getValueResourceByKey\(\\"(%s)\\"\)\)' % ms.KEY, mission),
                expected,
            )


if __name__ == "__main__":
    unittest.main()


class InjectBridge(unittest.TestCase):
    """`build --with-bridge` wires dcs-bridge.lua into the assembled mission, in all four places.

    Both serialisations, because the whole point of this tool is that two write the same table
    differently, and a malformed action block does not raise -- it loads a resource key that names
    nothing, in a mission somebody then opens in DCS.

    The test that earns its place is `test_the_result_passes_check`: it caught the injection
    appending to the FIRST trigrules array while the compiled call went to the end, which puts the
    two lists in a different order. It only shows up on a mission with two script-loading triggers,
    which the editor fixture has and the Persian Gulf demo does not -- so without it this shipped.
    """

    def _entries(self, mission, map_resource):
        return {
            "mission": mission.encode("utf-8"),
            ms.MAP_RESOURCE: map_resource.encode("utf-8"),
            ms.L10N + "skynet-iads-compiled.lua": b"-- skynet",
            ms.L10N + "mist_4_5_107.lua": b"-- mist",
        }

    def _inject(self, mission, map_resource, with_existing_bridge=False):
        """Run the three rewrites without touching the filesystem."""
        entries = self._entries(mission, map_resource)
        if with_existing_bridge:
            entries[ms.L10N + ms.BRIDGE] = b"-- bridge"
        new_map = ms.add_to_map_resource(map_resource, ms.BRIDGE_KEY, ms.BRIDGE)
        new_mission = ms.add_to_trig_actions(mission, ms.BRIDGE_KEY)
        new_mission = ms.add_to_trigrules(new_mission, ms.BRIDGE_KEY)
        entries[ms.MAP_RESOURCE] = new_map.encode("utf-8")
        entries["mission"] = new_mission.encode("utf-8")
        entries[ms.L10N + ms.BRIDGE] = b"-- bridge"
        return entries, new_mission, new_map

    def test_the_result_passes_check_dcs(self):
        entries, _, _ = self._inject(DCS_MISSION, DCS_MAP_RESOURCE)
        problems, _, _ = ms.check(entries)
        self.assertEqual(problems, [])

    def test_the_result_passes_check_editor(self):
        entries, _, _ = self._inject(EDITOR_MISSION, EDITOR_MAP_RESOURCE)
        problems, _, _ = ms.check(entries)
        self.assertEqual(problems, [])

    def test_the_key_lands_last_in_both_lists(self):
        for mission, mapres in ((DCS_MISSION, DCS_MAP_RESOURCE), (EDITOR_MISSION, EDITOR_MAP_RESOURCE)):
            with self.subTest(shape=mission[:20]):
                entries, _, _ = self._inject(mission, mapres)
                _, _, compiled = ms.check(entries)
                self.assertEqual(compiled[-1], ms.BRIDGE_KEY)

    def test_map_resource_gains_one_bracketed_entry(self):
        for mapres in (DCS_MAP_RESOURCE, EDITOR_MAP_RESOURCE):
            with self.subTest(shape=mapres[:20]):
                out = ms.add_to_map_resource(mapres, ms.BRIDGE_KEY, ms.BRIDGE)
                mapping = ms.parse_map_resource(out)
                self.assertEqual(mapping[ms.BRIDGE_KEY], ms.BRIDGE)
                self.assertEqual(len(mapping), len(ms.parse_map_resource(mapres)) + 1)
                # bracketed whatever the file's habit: the name has a hyphen, so it is no identifier
                self.assertIn('["%s"]' % ms.BRIDGE_KEY, out)

    def test_map_resource_keeps_the_indentation_it_found(self):
        self.assertIn('\n    ["%s"]' % ms.BRIDGE_KEY, ms.add_to_map_resource(DCS_MAP_RESOURCE, ms.BRIDGE_KEY, ms.BRIDGE))
        self.assertIn('\n  ["%s"]' % ms.BRIDGE_KEY, ms.add_to_map_resource(EDITOR_MAP_RESOURCE, ms.BRIDGE_KEY, ms.BRIDGE))

    def test_trigrules_indices_stay_contiguous(self):
        for mission in (DCS_MISSION, EDITOR_MISSION):
            with self.subTest(shape=mission[:20]):
                out = ms.add_to_trigrules(mission, ms.BRIDGE_KEY)
                start, end = ms.trigrules_of(out)
                for am in ms.first_matching(ms.ACTIONS_ARRAYS, out[start:end]):
                    idx = [int(b.group("n")) for b in ms.action_blocks(am.group("body") + "\n")]
                    self.assertEqual(idx, list(range(1, len(idx) + 1)))

    def test_the_clone_keeps_the_end_of_block_comment_only_where_it_belongs(self):
        # DCS closes every block with `-- end of [n]`; the editor writes none. A clone carrying the
        # wrong one still parses as Lua, so nothing downstream would complain.
        self.assertIn("-- end of [3]", ms.add_to_trigrules(DCS_MISSION, ms.BRIDGE_KEY))
        self.assertNotIn("-- end of [", ms.add_to_trigrules(EDITOR_MISSION, ms.BRIDGE_KEY))

    def test_injecting_twice_is_refused_by_the_archive_already_having_it(self):
        entries = self._entries(DCS_MISSION, DCS_MAP_RESOURCE)
        entries[ms.L10N + ms.BRIDGE] = b"-- bridge"
        order = list(entries)
        before = dict(entries)
        self.assertIsNone(ms.inject_bridge("demo-missions/x.miz", entries, order))
        self.assertEqual(entries, before)

    def test_a_mission_with_no_script_action_is_refused(self):
        self.assertIsNone(ms.add_to_trig_actions("mission = { trig = { actions = {} } }", ms.BRIDGE_KEY))
        self.assertIsNone(ms.add_to_map_resource("mapResource = \n{\n}\n", ms.BRIDGE_KEY, ms.BRIDGE))
