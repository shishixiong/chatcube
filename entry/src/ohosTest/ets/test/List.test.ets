import abilityTest from './Ability.test';
import kidsSubjectUtilsTest from './utils/KidsSubjectUtils.test';
import learningLedgerModelsTest from './utils/LearningLedgerModels.test';
import ledgerExtractUtilsTest from './utils/LedgerExtractUtils.test';
import lessonPlanModelsTest from './utils/LessonPlanModels.test';
import lessonPlanSectionRenderTest from './utils/LessonPlanSectionRender.test';
import lessonPlannerBaselineTest from './utils/LessonPlannerBaseline.test';
import lessonPlannerValidationTest from './utils/LessonPlannerValidation.test';
import lessonPlanSubjectUtilsTest from './utils/LessonPlanSubjectUtils.test';
import vocabRepeatValidationTest from './utils/VocabRepeatValidation.test';
import vocabLedgerSectionTest from './utils/VocabLedgerSection.test';
import stepAnswerPayloadTest from './utils/StepAnswerPayload.test';

export default function testsuite() {
  abilityTest();
  kidsSubjectUtilsTest();
  learningLedgerModelsTest();
  ledgerExtractUtilsTest();
  lessonPlanModelsTest();
  lessonPlanSectionRenderTest();
  lessonPlannerBaselineTest();
  lessonPlannerValidationTest();
  lessonPlanSubjectUtilsTest();
  vocabRepeatValidationTest();
  vocabLedgerSectionTest();
  stepAnswerPayloadTest();
}
