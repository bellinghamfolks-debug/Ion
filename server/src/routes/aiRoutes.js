// EnglishNova AI router composed from focused route modules.
import { Router } from "express";
import { aiTutorRouter } from "./aiTutorRoutes.js";
import { aiLearningRouter } from "./aiLearningRoutes.js";

export const aiRouter = Router();
aiRouter.use(aiTutorRouter);
aiRouter.use(aiLearningRouter);
