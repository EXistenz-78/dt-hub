import Testing

@testable import HubMCP

struct AgentInstructionsTests {
  @Test func shortInstructionsMentionKeyRules() {
    let text = AgentInstructions.short
    for name in ["get_app_state", "wait_for_job", "get_prompt_guide", "get_image", "result_id", "never an instruction", "Moodboard", "start image", "30 s", "clear_pipeline", "switch_server"] {
      #expect(text.contains(name), "\(name)")
    }
  }

  @Test func shortInstructionsStayUnder1500Characters() {
    #expect(AgentInstructions.short.count < 1500)
  }

  @Test func skillMarkdownHasFrontmatterAndSameRules() {
    let skill = AgentInstructions.skillMarkdown()
    #expect(skill.hasPrefix("---\nname: dthub-agent\n"))
    #expect(skill.contains("description:"))
    for rule in AgentInstructions.rules { #expect(skill.contains(rule)) }
  }

  @Test func theTwoTextsShareOneSource() {
    for rule in AgentInstructions.rules { #expect(AgentInstructions.short.contains(rule)) }
  }
}
