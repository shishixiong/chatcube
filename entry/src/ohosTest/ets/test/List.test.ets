import abilityTest from './Ability.test';
import kidsSubjectUtilsTest from './utils/KidsSubjectUtils.test';
import learningLedgerModelsTest from './utils/LearningLedgerModels.test';
import ledgerExtractUtilsTest from './utils/LedgerExtractUtils.test';
import vocabRepeatValidationTest from './utils/VocabRepeatValidation.test';
import vocabLedgerSectionTest from './utils/VocabLedgerSection.test';

export default function testsuite() {
  abilityTest();
  kidsSubjectUtilsTest();
  learningLedgerModelsTest();
  ledgerExtractUtilsTest();
  vocabRepeatValidationTest();
  vocabLedgerSectionTest();
}
