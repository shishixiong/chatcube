import abilityTest from './Ability.test';
import kidsSubjectUtilsTest from './utils/KidsSubjectUtils.test';
import learningLedgerModelsTest from './utils/LearningLedgerModels.test';
import ledgerExtractUtilsTest from './utils/LedgerExtractUtils.test';
import vocabRepeatValidationTest from './utils/VocabRepeatValidation.test';

export default function testsuite() {
  abilityTest();
  kidsSubjectUtilsTest();
  learningLedgerModelsTest();
  ledgerExtractUtilsTest();
  vocabRepeatValidationTest();
}
