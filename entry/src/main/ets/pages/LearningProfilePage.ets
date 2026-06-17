import { HdsNavigation, HdsNavigationTitleBarOptions, HdsNavigationTitleMode } from '@kit.UIDesignKit'
import { SettingsCompactTitleBarContent } from '../components/settings/SettingsCompactPageHeader'
import { SettingsPagePresentationMode } from '../config/SettingsDetailPresentation'
import { getSettingsPageContentMaxWidth } from '../utils/SettingsPageLayoutHelper'
import { getAppUiState } from '../state/AppUiState'
import {
  buildHdsTopNavigationTitleBarOptionsForPage,
  getHdsTopNavigationContentTopPadding,
  buildPointLightBorderEffect,
  getHdsStatusBarContentColor
} from '../utils/HdsVisualEffectUtil'
import {
  getChildProfileService,
  ChildKnowledgeProfile,
  SkillDimension
} from '../services/ChildProfileService'
import { SkillLevelDots } from '../components/SkillLevelDots'
import { formatRelativeTime } from '../utils/TimeFormatUtils'

const TAG = 'LearningProfilePage'
const TOTAL_LEVELS: number = 5

let learningProfilePagePathStack: NavPathStack | null = null

interface LearningSkillGroup {
  sectionKey: string
  sectionTitle: ResourceStr
  sectionIcon: Resource
  keys: string[]
}

const SKILL_GROUPS: LearningSkillGroup[] = [
  {
    sectionKey: 'math',
    sectionTitle: $r('app.string.learning_skill_section_math'),
    sectionIcon: $r('sys.symbol.plus'),
    keys: [
      'math_counting',
      'math_addition',
      'math_subtraction',
      'math_multiply',
      'math_divide',
      'math_shapes',
      'math_comparison',
      'math_time'
    ]
  },
  {
    sectionKey: 'english',
    sectionTitle: $r('app.string.learning_skill_section_english'),
    sectionIcon: $r('sys.symbol.text_alignleft'),
    keys: [
      'english_alphabet',
      'english_vocab',
      'english_sentence',
      'english_phonics',
      'english_writing'
    ]
  },
  {
    sectionKey: 'general',
    sectionTitle: $r('app.string.learning_skill_section_general'),
    sectionIcon: $r('sys.symbol.leaf'),
    keys: [
      'general_nature',
      'general_social',
      'general_life',
      'fine_motor',
      'chinese_writing'
    ]
  },
  {
    sectionKey: 'cognitive',
    sectionTitle: $r('app.string.learning_skill_section_cognitive'),
    sectionIcon: $r('sys.symbol.lightbulb'),
    keys: [
      'logic_puzzle',
      'observation',
      'categorization'
    ]
  }
]

@Entry
@ComponentV2
struct LearningProfilePage {
  private get topAvoidHeight(): number {
    return getAppUiState().topAvoidHeight
  }
  private get themePrimary(): string {
    return getAppUiState().themePrimary
  }
  private get themePrimaryLight(): string {
    return getAppUiState().themePrimaryLight
  }
  private get themeBackground(): string {
    return getAppUiState().themeBackground
  }
  private get themeSurface(): string {
    return getAppUiState().themeSurface
  }
  private get layoutSizeClass(): string {
    return getAppUiState().layoutSizeClass
  }
  private get windowWidthVp(): number {
    return getAppUiState().windowWidthVp
  }
  private get windowHeightVp(): number {
    return getAppUiState().windowHeightVp
  }
  private get settingsDetailPresentationMode(): string {
    return getAppUiState().settingsDetailPresentationMode
  }
  private get materialType(): number {
    return getAppUiState().materialType
  }
  private get materialLevel(): number {
    return getAppUiState().materialLevel
  }

  @Local profile: ChildKnowledgeProfile = new ChildKnowledgeProfile()
  @Local skillDefinitions: SkillDimension[] = []
  @Local isLoading: boolean = true

  private compactScroller: Scroller = new Scroller()
  private loadToken: number = 0

  private px2vp(px: number): number {
    return px / (this.getUIContext().getHostContext()?.resourceManager.getDeviceCapabilitySync().screenDensity ?? 3) * 160
  }

  aboutToAppear(): void {
    this.loadProfile()
  }

  private async loadProfile(): Promise<void> {
    const token = this.loadToken + 1
    this.loadToken = token
    this.isLoading = true
    try {
      const profile = await getChildProfileService().getProfile()
      if (token !== this.loadToken) {
        return
      }
      this.profile = profile
      this.skillDefinitions = getChildProfileService().getSkillDefinitions()
    } catch (error) {
      console.error(TAG, `Failed to load profile: ${JSON.stringify(error)}`)
    } finally {
      if (token === this.loadToken) {
        this.isLoading = false
      }
    }
  }

  private isEmpty(): boolean {
    if (this.profile.sessionCount > 0) {
      return false
    }
    const skills = this.profile.skills
    const keys = Object.keys(skills)
    for (let i = 0; i < keys.length; i++) {
      const skill = skills[keys[i]]
      if (skill.level > 0) {
        return false
      }
    }
    return true
  }

  private findSkillByKey(key: string): SkillDimension | null {
    if (this.profile.skills[key] !== undefined) {
      return this.profile.skills[key]
    }
    return null
  }

  private getSkillLabel(key: string, fallback: string): string {
    const skill = this.findSkillByKey(key)
    if (skill !== null && skill.label !== '') {
      return skill.label
    }
    return fallback
  }

  private getSkillLevel(key: string): number {
    const skill = this.findSkillByKey(key)
    if (skill === null) {
      return 0
    }
    return skill.level
  }

  private getLastAssessedLabel(key: string): string {
    const skill = this.findSkillByKey(key)
    if (skill === null || skill.lastAssessed <= 0) {
      return ''
    }
    return formatRelativeTime(skill.lastAssessed)
  }

  private getContentMaxWidth(): number {
    return getSettingsPageContentMaxWidth(this.layoutSizeClass, this.windowWidthVp, this.settingsDetailPresentationMode,
      this.windowHeightVp)
  }

  private isDetailPaneMode(): boolean {
    return this.settingsDetailPresentationMode === SettingsPagePresentationMode.DETAIL_PANE
  }

  private handleBack(): void {
    if (learningProfilePagePathStack !== null && learningProfilePagePathStack.size() > 0) {
      learningProfilePagePathStack.pop()
    }
  }

  private getCompactContentTopPadding(): number {
    return getHdsTopNavigationContentTopPadding(this.px2vp(this.topAvoidHeight), this.windowWidthVp,
      this.windowHeightVp)
  }

  private getCompactTitleBarOptions(): HdsNavigationTitleBarOptions {
    return buildHdsTopNavigationTitleBarOptionsForPage(this.materialType, this.materialLevel, this.windowWidthVp,
      this.windowHeightVp, (): void => this.CompactTitleStackBuilder())
  }

  private getChildAgeLabel(): string {
    if (this.profile.ageYears > 0) {
      return `${this.profile.ageYears} 岁`
    }
    return ''
  }

  private getChildNameDisplay(): string {
    return this.profile.childName !== '' ? this.profile.childName : '—'
  }

  @Builder
  private CompactTitleStackBuilder() {
    SettingsCompactTitleBarContent({
      title: $r('app.string.learning_profile_title'),
      onBack: () => {
        this.handleBack()
      }
    })
  }

  @Builder
  private DetailPaneHeader() {
    Column() {
      Row() {
        Text($r('app.string.learning_profile_title'))
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)
      }
      .width('100%')
      .height(64)
      .padding({ left: 24, right: 24 })
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .backgroundColor(this.themeBackground)
    .border({ width: { bottom: 1 }, color: $r('app.color.divider') })
  }

  @Builder
  private SectionTitle(title: ResourceStr) {
    Text(title)
      .fontSize(12)
      .fontWeight(FontWeight.Medium)
      .fontColor($r('app.color.text_secondary'))
      .padding({ left: 4, bottom: 6 })
      .width('100%')
  }

  @Builder
  private ChildHeaderCard() {
    Row({ space: 12 }) {
      Column() {
        SymbolGlyph($r('sys.symbol.person_2_fill'))
          .fontSize(20)
          .fontColor([this.themePrimary])
      }
      .width(40)
      .height(40)
      .borderRadius(20)
      .backgroundColor(this.themePrimaryLight)
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)

      Column({ space: 4 }) {
        Text(this.getChildNameDisplay())
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        Row({ space: 8 }) {
          if (this.getChildAgeLabel() !== '') {
            Text(this.getChildAgeLabel())
              .fontSize(12)
              .fontColor($r('app.color.text_secondary'))
          }
          if (this.profile.sessionCount > 0) {
            Text(`${this.profile.sessionCount} 次对话`)
              .fontSize(12)
              .fontColor($r('app.color.text_tertiary'))
          }
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .padding(14)
    .backgroundColor(this.themeSurface)
    .borderRadius(16)
    .border({ width: 1, color: $r('app.color.divider') })
    .visualEffect(buildPointLightBorderEffect())
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  private OverallNoteCard() {
    Column({ space: 8 }) {
      Text($r('app.string.learning_section_overall_note'))
        .fontSize(12)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_secondary'))

      Text(this.profile.overallNote !== '' ? this.profile.overallNote : '—')
        .fontSize(13)
        .fontColor($r('app.color.text_primary'))
        .lineHeight(20)
        .maxLines(6)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
    }
    .width('100%')
    .padding(14)
    .backgroundColor(this.themeSurface)
    .borderRadius(16)
    .border({ width: 1, color: $r('app.color.divider') })
    .visualEffect(buildPointLightBorderEffect())
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  private SkillChipList(title: ResourceStr, items: string[]) {
    Column({ space: 8 }) {
      Text(title)
        .fontSize(12)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_secondary'))

      if (items.length === 0) {
        Text('—')
          .fontSize(13)
          .fontColor($r('app.color.text_tertiary'))
      } else {
        Flex({ wrap: FlexWrap.Wrap }) {
          ForEach(items, (item: string, index: number) => {
            Text(this.getSkillLabel(item, item))
              .fontSize(12)
              .fontColor(this.themePrimary)
              .padding({ left: 10, right: 10, top: 5, bottom: 5 })
              .borderRadius(12)
              .backgroundColor(this.themePrimaryLight)
              .margin({ right: 6, bottom: 6 })
          }, (item: string, index: number) => `${index}_${item}`)
        }
      }
    }
    .width('100%')
    .padding(14)
    .backgroundColor(this.themeSurface)
    .borderRadius(16)
    .border({ width: 1, color: $r('app.color.divider') })
    .visualEffect(buildPointLightBorderEffect())
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  private StrengthsWeakCard() {
    Row({ space: 10 }) {
      Column() {
        this.SkillChipList($r('app.string.learning_section_strengths'), this.profile.strengths)
      }
      .layoutWeight(1)
      Column() {
        this.SkillChipList($r('app.string.learning_section_weak_areas'), this.profile.weakAreas)
      }
      .layoutWeight(1)
    }
    .width('100%')
  }

  @Builder
  private SkillRow(key: string) {
    Row() {
      Text(this.getSkillLabel(key, key))
        .fontSize(14)
        .fontColor($r('app.color.text_primary'))
        .layoutWeight(1)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })

      SkillLevelDots({ level: this.getSkillLevel(key) })

      Text(this.getLastAssessedLabel(key))
        .fontSize(11)
        .fontColor($r('app.color.text_tertiary'))
        .margin({ left: 8 })
        .width(64)
        .maxLines(1)
        .textAlign(TextAlign.End)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width('100%')
    .padding({ top: 10, bottom: 10, left: 14, right: 14 })
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  private SkillGroupCard(group: LearningSkillGroup) {
    Column() {
      ForEach(group.keys, (key: string, index: number) => {
        Column() {
          this.SkillRow(key)
          if (index < group.keys.length - 1) {
            Divider()
              .color($r('app.color.divider'))
              .margin({ left: 14, right: 14 })
          }
        }
      }, (key: string) => key)
    }
    .width('100%')
    .backgroundColor(this.themeSurface)
    .borderRadius(16)
    .clip(true)
    .border({ width: 1, color: $r('app.color.divider') })
    .visualEffect(buildPointLightBorderEffect())
  }

  @Builder
  private SkillsGrid() {
    Column({ space: 14 }) {
      ForEach(SKILL_GROUPS, (group: LearningSkillGroup) => {
        Column({ space: 6 }) {
          Row({ space: 6 }) {
            SymbolGlyph(group.sectionIcon)
              .fontSize(13)
              .fontColor([this.themePrimary])
            Text(group.sectionTitle)
              .fontSize(13)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.text_primary'))
          }
          .width('100%')
          .alignItems(VerticalAlign.Center)

          this.SkillGroupCard(group)
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
      }, (group: LearningSkillGroup) => group.sectionKey)
    }
    .width('100%')
  }

  @Builder
  private EmptyState() {
    Column({ space: 8 }) {
      SymbolGlyph($r('sys.symbol.person'))
        .fontSize(48)
        .fontColor([$r('app.color.text_tertiary')])
        .margin({ bottom: 4 })
      Text($r('app.string.learning_profile_empty_title'))
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_secondary'))
      Text($r('app.string.learning_profile_empty_desc'))
        .fontSize(13)
        .fontColor($r('app.color.text_tertiary'))
        .textAlign(TextAlign.Center)
        .padding({ left: 24, right: 24 })
    }
    .width('100%')
    .padding({ top: 64, bottom: 64 })
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  private PageContent() {
    Scroll(this.compactScroller) {
      Row() {
        Column() {
          if (!this.isDetailPaneMode()) {
            Blank()
              .width('100%')
              .height(this.getCompactContentTopPadding())
          }

          if (this.isEmpty() && !this.isLoading) {
            this.EmptyState()
          } else {
            this.ChildHeaderCard()

            if (this.profile.overallNote !== '') {
              Column() {
                this.OverallNoteCard()
              }
              .width('100%')
              .margin({ top: 14 })
              .alignItems(HorizontalAlign.Start)
            }

            Column() {
              this.StrengthsWeakCard()
            }
            .width('100%')
            .margin({ top: 14 })
            .alignItems(HorizontalAlign.Start)

            Column() {
              this.SkillsGrid()
            }
            .width('100%')
            .margin({ top: 18 })
            .alignItems(HorizontalAlign.Start)
          }

          Blank().width('100%').height(28)
        }
        .width('100%')
        .constraintSize({ maxWidth: this.getContentMaxWidth() })
      }
      .width('100%')
      .justifyContent(FlexAlign.Center)
      .padding({ left: 16, right: 16 })
    }
    .width('100%')
    .layoutWeight(1)
    .scrollBar(BarState.Off)
  }

  build() {
    Column() {
      if (this.isDetailPaneMode()) {
        Column() {
          this.DetailPaneHeader()
          this.PageContent()
        }
        .width('100%')
        .layoutWeight(1)
      } else {
        HdsNavigation() {
          this.PageContent()
        }
        .width('100%')
        .height('100%')
        .backgroundColor(this.themeBackground)
        .titleBar(this.getCompactTitleBarOptions())
        .bindToScrollable([this.compactScroller])
        .titleMode(HdsNavigationTitleMode.MINI)
        .systemBarStyle(
          { statusBarContentColor: getHdsStatusBarContentColor() },
          { statusBarContentColor: getHdsStatusBarContentColor() }
        )
        .hideBackButton(true)
        .hideToolBar(true)
        .mode(NavigationMode.Stack)
        .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP])
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.themeBackground)
  }
}

@Builder
export function LearningProfilePageBuilder(name: string, param: Object) {
  NavDestination() {
    LearningProfilePage()
  }
  .hideTitleBar(true)
  .hideBackButton(true)
  .onReady((context: NavDestinationContext) => {
    learningProfilePagePathStack = context.pathStack
  })
  .onBackPressed((): boolean => {
    if (learningProfilePagePathStack !== null && learningProfilePagePathStack.size() > 0) {
      learningProfilePagePathStack.pop()
    }
    return true
  })
}
